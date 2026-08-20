# torchcomms-perf-alcf

Collective-communication benchmarking for [torchcomms](https://github.com/meta-pytorch/torchcomms)
on ALCF Intel GPU systems (Sunspot, Aurora), using the perf harness from
upstream **draft PR #2633**.

Works against **any torchcomms installation** — the harness runs from a
standalone directory and imports `torchcomms` from wherever it happens to be
installed. Nothing here ever writes to your torchcomms install.

```bash
git clone <this-repo> && cd torchcomms-perf-alcf
./bin/tc-perf-setup     # fetch the harness, flatten it, patch it
./bin/tc-perf-doctor    # preflight
qsub -A <Project> jobs/smoke.pbs
```

---

## Why this repo exists

The collective perf benchmarks live only on
[PR #2633](https://github.com/meta-pytorch/torchcomms/pull/2633), which is an
**open draft that we assume will never merge**. Three things stand between that
branch and a number you can trust on Aurora:

1. **You cannot just put the PR clone on `PYTHONPATH`.** It ships a full
   `torchcomms/` package directory, so it *replaces* your installed torchcomms
   instead of extending it, and dies at
   `ModuleNotFoundError: No module named 'torchcomms._comms'` — the compiled
   `.so` exists only in the install. `tc-perf-setup` copies the ~18 perf scripts
   into a flat directory and rewrites their imports, so the perf code comes from
   the flat dir and `torchcomms` from your install. That decoupling is what makes
   this installation-agnostic.

2. **The launcher does not match.** The harness assumes `torchrun`. PBS/PALS
   exports `PMIX_RANK` and `PALS_LOCAL_RANKID`; torchcomms' rank discovery looks
   at `OMPI_COMM_WORLD_*`, `RANK`/`WORLD_SIZE`, `SLURM_*`, `PMI_*` — and matches
   none of them. `tc-perf-env` maps one onto the other, per rank.

3. **Two real bugs in the draft.** Both are carried as patches in `patches/`
   (see below).

---

## Commands

| Command | Purpose |
|---|---|
| `tc-perf-setup` | Fetch PR #2633, build the flat harness, apply patches. Re-runnable. |
| `tc-perf-doctor` | Preflight. Every check exists because something once went wrong. |
| `tc-perf-smoke` | Tiny 3-adapter run. Proves the pipe is connected; not a measurement. |
| `tc-perf-run` | The real benchmark launcher. |
| `tc-perf-analyze` | Wrapper around upstream `analyze_perf.py` (plots + regression reports). |
| `tc-perf-env` | Per-rank shim. Runs *inside* `mpiexec`; you don't call it directly. |

---

## From scratch on a new machine

```bash
# 1. Get the repo (any filesystem your compute nodes can read)
git clone <this-repo> && cd torchcomms-perf-alcf

# 2. Build the harness. Clones torchcomms into .cache/ (~2 min), extracts the
#    pinned commit, flattens imports, applies patches.
./bin/tc-perf-setup

#    Already have a torchcomms clone? Skip the download:
TCPERF_UPSTREAM_DIR=/path/to/torchcomms ./bin/tc-perf-setup

# 3. Preflight. Safe on a login node.
./bin/tc-perf-doctor

# 4. Smoke test in a real allocation
qsub -A <YourProject> jobs/smoke.pbs

# 5. Full sweep
qsub -A <YourProject> jobs/sweep.pbs

# 6. Analyze
./bin/tc-perf-analyze results/<run-id> --baseline c10d
```

The build is reproducible: a from-scratch clone on Aurora produced a
`perf_standalone/` **byte-identical** to the one built from an existing Sunspot
clone.

---

## Using a different torchcomms installation

Nothing needs to change. Activate whichever environment you want measured and
run — the harness imports `torchcomms` from that environment:

```bash
conda activate /path/to/some/other/frameworks_env
./bin/tc-perf-doctor          # confirms which torchcomms it found
./bin/tc-perf-run --rpn 12 --collective all_reduce
```

`tc-perf-doctor` prints the resolved `torchcomms.__file__`, and every results
directory carries a `run_metadata.txt` recording the conda prefix, build tag,
upstream commit, patch list, and the full `CCL_*`/`ZE_*` environment. Check that
file before comparing two runs.

---

## Adding a site

Site-specific values live in `sites/<name>.sh` and nowhere else. To add one:

```bash
cp sites/generic.sh sites/mymachine.sh
$EDITOR sites/mymachine.sh        # HSN suffix, tiles/node, module load, CCL defaults
TCPERF_SITE=mymachine ./bin/tc-perf-doctor
```

Detection is by hostname in `sites/common.sh`; `TCPERF_SITE` overrides it.

The one value worth getting right is `TCPERF_HSN_SUFFIX`, which turns a bare
nodename from `PBS_NODEFILE` into a rendezvous address. On Aurora:

```
x4305c0s1b0n0-hsn0.hsn.cm.aurora.alcf.anl.gov  -> 1 address    <- use this
x4305c0s1b0n0.hsn.cm.aurora.alcf.anl.gov       -> 8 addresses  <- flaky rendezvous
```

`tc-perf-doctor` warns when the master address resolves to more than one.

---

## The patches

Both fix real bugs in the draft PR. `tc-perf-setup` applies them idempotently
and detects already-applied ones, so re-running is safe. `--no-patch` gives you
vanilla upstream.

**`0001-bind-device-by-local-rank.patch`** — upstream binds accelerators with
`rank % device_count` using the **global** rank, which is correct only when
ranks-per-node equals devices-per-node. On a 12-tile node:

| layout | result |
|---|---|
| 2 nodes × 12 rpn | correct by accident |
| 2 nodes × 2 rpn | **wrong** — ranks 2,3 bind tiles 2,3 instead of 0,1 |
| 2 nodes × 6 rpn | **wrong** — ranks 6–11 bind tiles 6–11 instead of 0–5 |

We hit this live in our first multi-node run. It fails *silently*: the benchmark
completes and reports numbers for a tile pairing you did not ask for. The fix
reads a node-local rank from the environment, falling back to the global rank
when nothing is set — so an un-wrapped run is never worse than upstream.

**`0002-record-torchcomms-build-tag.patch`** — upstream computes
`torchcomms_version` into a local variable and never assigns it, so every CSV
reports `TorchCommsVersion=n/a`. And on both Sunspot and Aurora the installed
torchcomms has no `__version__` at all, so merely fixing the assignment would
yield `unknown`. The patch assigns the field and falls back to
`$TORCHCOMMS_BUILD_TAG` (the frameworks version, or the conda env name), which
is what actually distinguishes builds.

Neither is upstreamed, because #2633 is a draft we assume will not merge. If it
is ever force-pushed, `tc-perf-setup` fails loudly with the SHA mismatch rather
than building something unverified.

### Your own patches survive

`perf_standalone/` is not disposable. `tc-perf-setup` keeps a pristine copy of
each upstream file in `perf_standalone/.upstream/` and refuses to overwrite
anything that differs from it:

```
KEEP (locally modified): all_reduce_perf.py
```

`--check` reports drift without writing; `--force` resets after snapshotting to
`perf_standalone.bak.<timestamp>/`.

---

## Reading the results

Each run produces:

```
results/<run-id>/
├── run_metadata.txt          <- read this before trusting anything
├── torchcomms/*.csv
├── c10d/*.csv
├── c10d_torchcomms/*.csv
└── analysis/                 <- after tc-perf-analyze
```

The three adapters are the point of the exercise: `torchcomms` is the new API,
`c10d` is stock `torch.distributed`, and `c10d_torchcomms` is c10d routed
through torchcomms — the shim that carries the migration, and the one whose
overhead you most want to know.

Caveats worth stating whenever you report numbers:

- **Run at least twice.** One run tells you nothing about the noise floor.
- **`--sync-interval 1`** gives per-iteration min/max. At `0` the harness reports
  `min == max == avg`, which hides the spread entirely.
- **First-touch cost pollutes the smallest size.** Our first smoke run showed
  14098 µs at 1 KiB against ~113 µs at 2 KiB — allocator/init cost, not latency.
  Use a larger `--warmup` (the sweep job uses 50) and treat the first point with
  suspicion.
- **`CCL_ATL_SYNC_COLL=1` / `CCL_OP_SYNC=1`** are frameworks-module defaults that
  force synchronous collectives. We deliberately do not override them — they are
  what users actually run under — but they mute `--async` differences, so say so.

---

## Layout

```
bin/            the six commands
sites/          per-machine config (the ONLY place hostnames belong)
patches/        our fixes to the draft PR, with rationale in each header
jobs/           ready-to-qsub PBS scripts
upstream.lock   pinned PR number, commit SHA, file hashes
perf_standalone/  generated; your patches here are preserved
```

---

## Troubleshooting

**`ModuleNotFoundError: No module named 'torchcomms._comms'`**
A torchcomms source tree is shadowing your install. Remove any torchcomms clone
from `PYTHONPATH`. `tc-perf-doctor` diagnoses this specifically.

**A script produces no output at all and exits instantly**
Lmod's `module` is a shell function whose generated code references
`$ZSH_EVAL_CONTEXT`, which does not exist in bash. Under `set -u` that is an
unbound-variable error that kills the script — silently, if stderr is
redirected. This cost us an afternoon. All module calls here are wrapped in
`set +u` and never swallow stderr; keep it that way.

**Ranks hang at startup**
`MASTER_ADDR` differs between ranks. It must be computed **once** in the outer
job script from `PBS_NODEFILE`, never from `hostname` inside the per-rank
wrapper (where every rank would elect itself). Check `run_metadata.txt`.

**`patch FAILED` during setup**
Upstream moved under a patch. Either regenerate it against the new commit, or
run `tc-perf-setup --no-patch` for the vanilla harness and re-apply by hand.
