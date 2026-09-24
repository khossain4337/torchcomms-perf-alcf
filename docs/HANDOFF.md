# HANDOFF

Resume point for this work. Written 2026-08-20. Read this first, then
`../README.md` for how to actually run things.

---

## In one paragraph

We are benchmarking torchcomms collectives on ALCF Intel GPUs using the perf
harness from **draft PR #2633** (assumed never to merge). Three obstacles —
package shadowing, a launcher mismatch, and two real bugs in the draft — are all
solved, and the solutions are packaged in this repo. The tooling is verified
end to end. **What is missing is data:** no production benchmark has been run
through the repo yet. That is the next step, and it needs a Sunspot allocation.

---

## Where things stand

| | |
|---|---|
| **Tooling** | Complete and tested. 2 commits, 18 tracked files. |
| **Bring-up on Sunspot** | Phases 0, 1, 2 all PASS (smoke test, all three adapters). |
| **Patches** | Both written, applied automatically, verified idempotent. |
| **Production data** | **None yet.** This is the gap. |

### Three buckets — keep these distinct when reporting status

1. **Run for real on Sunspot (2026-08-20):** three-adapter smoke test
   (`torchcomms`, `c10d`, `c10d_torchcomms`) at 2 nodes × 2 ranks, `all_reduce`,
   1–4 KiB, 20 iters. All three PASS. Device: Intel Data Center GPU Max 1550,
   xccl `20220100`. CSVs written.
2. **Verified on Aurora, tooling only (aurora-uan-0011, 2026-08-20):**
   from-scratch clone + build is byte-reproducible against the Sunspot-clone
   build; both patches apply, round-trip, and are detected as already-applied;
   local edits survive refresh; `--force` resets after snapshotting; the full
   analyze pipeline produces plots and regression reports from synthetic CSVs;
   the rank shim maps PALS vars correctly (rank 2 → local 0, rank 3 → local 1).
3. **Never run:** any real multi-node benchmark *through this repo*. Also never
   checked: **whether the three adapters actually report different latencies.**
   That is the entire premise of the exercise and it is still unverified.

---

## Next actions, in order

1. **Get a Sunspot allocation and run the smoke test through the repo.**
   ```bash
   qsub -A <YourProject> jobs/smoke.pbs
   ```
   This re-validates Phase 2 through the new code path. Expect PASS.

2. **Answer the open question — do the adapters differ?**
   ```bash
   for a in torchcomms c10d c10d_torchcomms; do
       echo "== $a"; cut -d, -f4,10 results/<run-id>/$a/all_reduce.csv
   done
   ```
   (fields 4 and 10 are `SendMsgSize(B)` and `LatAvg(us)`.) If the three are
   identical to the microsecond, something is wrong — most likely the sticky
   `use_torchcomms` flag, though separate `mpiexec` calls should make that
   impossible. Investigate before trusting any comparison.

3. **Run the production sweep.**
   ```bash
   qsub -A <YourProject> jobs/sweep.pbs
   ```
   Defaults: 2 repeats × rungs {2, 12} rpn × 4 collectives, 1 KiB–64 MiB,
   `--warmup 50 --iters 100 --sync-interval 1`. On `select=2` the 12-rpn rung
   is the first number that includes the HSN fabric.

4. **Analyze.**
   ```bash
   for d in results/sweep-rep*/; do ./bin/tc-perf-analyze "$d" --baseline c10d; done
   ```

5. **Confirm the first-touch outlier is gone.** Our smoke run showed 14098 µs at
   1 KiB against ~113 µs at 2 KiB — a 125× init-cost artifact. `--warmup 50`
   should fix it. If it does not, raise warmup further and note it.

---

## Standing constraints (set by the user, 2026-08-20)

- **Sunspot now, Aurora soon.** Both profiles exist; Aurora's HSN suffix is
  DNS-verified but the site has not been exercised in a real job.
- **PBS/PALS only.** No Slurm, no torchrun support wanted. Do not add a launcher
  abstraction layer.
- **PR #2633 stays unmerged.** Carry the fixes as local patches; do not build
  machinery that waits on upstream.
- **Never modify the installed torchcomms.** Everything happens in
  `perf_standalone/`. This is a hard boundary — it was stated explicitly.
- **`perf_standalone/` is not disposable.** It carries patches. The `.upstream/`
  reference mechanism protects local edits; do not replace it with a plain copy.

---

## The five things most likely to bite a new session

1. **`set -u` + Lmod `module` = silent death.** Lmod's `module` is a shell
   function whose generated code references `$ZSH_EVAL_CONTEXT`, undefined in
   bash. Under `set -u` that is an unbound-variable error that kills the script —
   with *zero output* if stderr is redirected. Cost ~30 min of debugging. Every
   module call in this repo is wrapped in `set +u` and never swallows stderr.
   Scripts also echo on line 1 so "no output" reliably means "never started."

2. **`PYTHONPATH=<clone>/comms` does not work.** The clone ships a full
   `torchcomms/` package dir, so it *replaces* the installed package and dies at
   `ModuleNotFoundError: No module named 'torchcomms._comms'`. The flat-dir
   rewrite exists precisely to avoid this. `tc-perf-doctor` diagnoses it by name.

3. **`MASTER_ADDR` must be computed once, outside `mpiexec`.** `tc-perf-env` runs
   per rank; deriving the address from `hostname` there would make every rank
   elect itself. It comes from `PBS_NODEFILE` (same file for all ranks) or from
   the outer script.

4. **`python` may not exist until the frameworks module loads.** Bit us in
   `tc-perf-analyze`. All scripts now bootstrap the environment first.

5. **The two filesystems are mutually invisible.** `/lus/tegu` is unreachable
   from flare nodes and vice versa. Do not assume a path exists on both.

---

## Repo map

```
bin/            six commands (see README table)
sites/          per-machine config — the ONLY place hostnames belong
patches/        our two fixes, rationale in each header
jobs/           qsub-ready PBS scripts
docs/           METHODOLOGY.md (what the numbers mean), HANDOFF.md (this file)
upstream.lock   pinned PR number, commit SHA, file hashes
perf_standalone/  GENERATED by tc-perf-setup; gitignored; patches preserved
```

Rebuild everything from the 18 tracked files with `./bin/tc-perf-setup`.

---

## Upstream pin

| | |
|---|---|
| RFC | [#2634](https://github.com/meta-pytorch/torchcomms/issues/2634), pkourdis (Intel), opened 2026-05-20 |
| Impl PR | [#2633](https://github.com/meta-pytorch/torchcomms/pull/2633) — open **DRAFT**, no reviews |
| Pinned SHA | `157738bca399d48596d8fca67ca8c8b8abab2fa0` |
| Branch | `pkourdis:perf/multi-adapter-benchmarks` → `meta-pytorch:main` |
| Scope | 20 files, +2565/−1073, all under `comms/torchcomms/tests/perf/py/` |

Pure test-harness code — nothing touches the library, C++ layer, or build. That
is why it only has to *import against* the installed torchcomms rather than match
its build, and why this works against arbitrary installations.

The commit is ~2 months older than the installed runtime (torchcomms 0.3.1-rc1,
built 2026-07-22). No incompatibility observed so far.

**If #2633 is force-pushed:** `tc-perf-setup` fails loudly with a SHA mismatch
rather than building something unverified. Update `UPSTREAM_SHA` in
`upstream.lock`, re-run `tc-perf-setup --check`, and expect the patches to need
a rebase.

Note: the pinned commit turned out to be reachable from `origin`'s refs, so a
plain clone suffices; the `refs/pull/2633/head` fetch remains as a fallback.

---

## Our two patches

**`0001-bind-device-by-local-rank.patch`** — upstream binds accelerators with
`rank % device_count` using the **global** rank, correct only when
ranks-per-node equals devices-per-node:

| layout | result |
|---|---|
| 2 nodes × 12 rpn | correct by accident |
| 2 nodes × 2 rpn | **wrong** — ranks 2,3 bind tiles 2,3 instead of 0,1 |
| 2 nodes × 6 rpn | **wrong** — ranks 6–11 bind tiles 6–11 instead of 0–5 |

Confirmed live in our Phase 2 run. Fails silently — the benchmark completes and
reports numbers for a tile pairing you did not ask for. **Any measurement taken
before this patch, at any layout other than full-node, is suspect.** The fix
falls back to the global rank when no local-rank env var is set, so it can never
make an un-wrapped run worse.

**`0002-record-torchcomms-build-tag.patch`** — upstream computes
`torchcomms_version` into a local and never assigns it, so every CSV reports
`TorchCommsVersion=n/a` (confirmed in real output). Compounding it, **neither
Sunspot nor Aurora's installed torchcomms has a `__version__` attribute**, so
merely fixing the assignment would yield `"unknown"`. The patch assigns the field
*and* falls back to `$TORCHCOMMS_BUILD_TAG`, which `tc-perf-run` resolves from
`FRAMEWORKS_VERSION`, else the conda env name. Without this, CSVs taken months
apart are indistinguishable — which defeats the RFC's stated purpose.

Both are genuine upstream bugs. **Worth reporting on PR #2633** even though we
are not waiting for it — the author is at Intel and works on XPU too. Not yet
filed.

---

## Design decisions worth not re-litigating

- **Three separate `mpiexec` calls, never `--all-comm-adapters`.** The harness
  sets `dist_config.use_torchcomms = True` for the `c10d_torchcomms` adapter and
  never resets it, so any adapter run afterward *in the same process* is still
  routed through torchcomms while reporting as plain c10d. Separate processes
  make that structurally impossible. Do not "optimize" this into one run.
- **Flat dir + import rewrite, not `PYTHONPATH`.** See trap #2 above. The side
  benefit is decoupling from the PR branch entirely.
- **Site config in `sites/*.sh` only.** No hostname, module name, or CCL default
  belongs in `bin/`.
- **`CCL_ATL_SYNC_COLL=1` / `CCL_OP_SYNC=1` are left alone.** They are frameworks
  module defaults that force synchronous collectives and mute `--async`
  differences. We measure what users actually run under — but every async claim
  must state they were set. `tc-perf-doctor` warns; `run_metadata.txt` records
  the full `CCL_*` environment.
- **Analysis has no torch dependency.** `analyze_perf.py` imports only argparse,
  pathlib, matplotlib, pandas — so CSVs can be analyzed on a laptop.

---

## Known gaps and loose ends

- **No production data yet.** The headline gap.
- **Aurora never exercised in a real job.** The profile is written and its DNS
  suffix verified, but no allocation has run there.
- **Repo lives only on flare**, at
  `/lus/flare/projects/datasets/softwares/testing/torchcomm_example/torchcomms-perf-alcf`.
  It has no remote. Push it somewhere, or `git clone` it to tegu, before
  colleagues can use it.
- **The loose scripts in the parent directory still exist** (`perf_env.sh`,
  `phase2_smoke.sh`, `setup_perf_standalone.sh`). They work but are superseded;
  new work goes in the repo. `MEMORY_2026-08-20.md` and `PLAN.md` there carry the
  full bring-up history and now point here.
- **Upstream bugs not reported** to PR #2633.
- **`send_recv` needs an even rank count** and skips otherwise.
- **`TEST_FULL_SWEEP=0`** is an undocumented upstream escape hatch that shrinks
  defaults (max_size 64 MiB → 1 KiB, warmup 5 → 1, iters 1000 → 3). Useful for
  cheap tests; not used by our jobs, which set sizes explicitly.
