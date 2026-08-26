# Methodology notes

Things that change what the numbers mean. Read before publishing any of them.

## Adapters

Three code paths, one workload:

| adapter | flag | what it exercises |
|---|---|---|
| `torchcomms` | *(none)* | the new torchcomms API directly |
| `c10d` | `--c10d` | stock `torch.distributed` |
| `c10d_torchcomms` | `--c10d-torchcomms` | c10d routed through torchcomms |

The third is the interesting one: it is the compatibility shim that carries
existing `torch.distributed` code onto torchcomms, so its delta against plain
`c10d` is the migration cost.

**We run each adapter as a separate `mpiexec`.** The harness's
`--all-comm-adapters` mode sets `dist_config.use_torchcomms = True` when it
reaches `c10d_torchcomms` and never resets it, so any adapter run afterward in
the same process is still routed through torchcomms while reporting itself as
plain c10d. Separate processes make that impossible. Do not "optimize" this
into a single run.

## Warmup and the first data point

Our first smoke run reported **14098 µs at 1 KiB** and ~113 µs at 2 KiB — a 125×
outlier. That is first-touch allocation and lazy init, not communication
latency. Mitigations, in order of effectiveness:

- `--warmup 50` or more (the sweep job uses 50; the harness default is 5)
- discard the smallest size when reporting
- check whether `LatMin` is sane while `LatAvg` is not — that pattern means one
  slow iteration, i.e. init cost, not a slow path

## `--sync-interval`

| value | behaviour |
|---|---|
| `0` | bulk timing: `LatMin == LatMax == LatAvg`. Spread is invisible. |
| `1` | per-iteration timing: real min/max. **Use this for anything you report.** |
| `N` | windowed over N iterations |

The smoke test uses `0` on purpose (it is checking connectivity, not
performance). Everything else should use `1`.

## Synchronous-collective confound

The frameworks module sets `CCL_ATL_SYNC_COLL=1` and `CCL_OP_SYNC=1`. These
force synchronous collectives, which compresses the difference between `--async`
and sync dispatch to nearly nothing.

**We override them to 0 by default** (changed 2026-08-26). `TCPERF_CCL_SYNC`
selects the behaviour:

| value | effect | what it measures |
|---|---|---|
| `0` (default) | both exported as `0` per-rank | the library's own asynchrony |
| `unset` | both removed; oneCCL's built-in default applies | oneCCL unconfigured |
| `keep` | module values left alone | what a user gets by `ml add frameworks` |

These are different questions, not better and worse answers. `0` isolates
torchcomms/oneCCL behaviour from a site policy that happens to serialise it;
`keep` measures what someone actually experiences. **A report must say which
one it used** — `run_metadata.txt` records it as `ccl_sync_mode=`, and
`tc-perf-env` prints it on rank 0 at the top of every run.

`0` and `unset` are not equivalent: one asserts a value, the other declines to.
If a run under `0` looks identical to one under `keep`, try `unset` before
concluding the setting does not matter.

### Where the override lives, and why it cannot live anywhere else

In `bin/tc-perf-env`, the per-rank shim — **not** in `run.sh`, a job script, or
a site profile. `tc-perf-run` calls `tcperf_load_env`, which runs
`module add frameworks`, which re-sets both variables to `1`. Anything exported
before that point is silently overwritten before the ranks ever start. The shim
runs inside `mpiexec`, after the module load, so it has the last word.

This also means `run_metadata.txt`'s `CCL_*` listing is captured *pre*-override
and can read `CCL_OP_SYNC=1` for a run whose ranks used `0`. Those two lines are
annotated in the file; `ccl_sync_mode=` is the authoritative one.

## Bus bandwidth

The harness uses the standard ring formula:

```
bus_bw = algo_bw * 2 * (num_ranks - 1) / num_ranks / 1000
```

This is the right model for ring all-reduce. It is **not** right for every
collective in the suite — treat `BusBw` as comparable across adapters at a fixed
collective and rank count, not as an absolute hardware utilization figure.

## Rank layouts worth running

| layout | what it isolates |
|---|---|
| 1 node × 2 ranks | single-tile-pair, intra-card |
| 1 node × 12 ranks | full node, intra-node scale-up |
| 2 nodes × 12 ranks | adds the HSN; the first number that includes the fabric |

Before patch 0001, only the 12-rpn layouts were accidentally correct — the
others silently benchmarked the wrong tiles. See the README.

## Repeats

Run everything at least twice (`REPEATS` in `jobs/sweep.pbs`, default 2). Node
placement, other jobs on the fabric, and thermal state all move these numbers.
A single run has no error bar and should not be compared against another single
run.
