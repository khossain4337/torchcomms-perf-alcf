# QUICKSTART — Sunspot interactive session

Everything you need is in this repo. Nothing to install, nothing to fetch.

## 0. Re-syncing from flare later

`/lus/flare` and `/lus/tegu` are mutually invisible, so this is a network copy
either way. Pulling from Sunspot:

    rsync -av \
      --exclude 'results/' --exclude 'logs/' --exclude '.cache/' \
      --exclude '__pycache__/' --exclude '*.pyc' --exclude 'perf_standalone.bak.*/' \
      <flare-host>:/lus/flare/projects/datasets/softwares/testing/torchcomm_example/torchcomms-perf-alcf/ \
      ./

Keep `--exclude 'results/'` in place: results are per-machine, and copying them
between the two is the easiest way to end up comparing Aurora numbers against
Sunspot numbers without noticing. `.cache/` is a full torchcomms clone that is
not needed here at all — `perf_standalone/` is already built and patched.

## 1. Get nodes

    qsub -I -l select=4 -l walltime=6:00:00 -q workq -l filesystems=home:tegu -A datascience

## 2. On the compute node

    cd <this repo>
    ml add frameworks
    bash run.sh preflight

Read the doctor output. Then, in order:

    bash run.sh smoke      # ~3 min   all three adapters, tiny sizes
    bash run.sh check      # instant  DO the three adapters differ?
    bash run.sh ladder     # ~30 min  first real data
    bash run.sh analyze    # plots + regression reports

`bash run.sh` and `./run.sh` are equivalent, and work from any directory.

## Why `check` matters

Whether `torchcomms`, `c10d`, and `c10d_torchcomms` actually report *different*
latencies has never been verified. That is the premise the whole comparison
rests on. If the three are identical to the microsecond, stop and investigate
before spending allocation time on the ladder.

## Knobs

    COLLECTIVES="all_reduce"   bash run.sh ladder
    NODE_RUNGS="1 2 4"         bash run.sh ladder
    RPN_RUNGS="2 12"           bash run.sh ladder
    REPEATS=3                  bash run.sh sweep
    TCPERF_CCL_SYNC=keep       bash run.sh ladder    # see below
    DRY=1                      bash run.sh ladder    # print commands, launch nothing

### `TCPERF_CCL_SYNC`

The frameworks module forces synchronous collectives (`CCL_OP_SYNC=1`,
`CCL_ATL_SYNC_COLL=1`). **We now override both to 0 by default.**

    TCPERF_CCL_SYNC=0        the shim exports both as 0     <- default
    TCPERF_CCL_SYNC=unset    the shim removes both entirely
    TCPERF_CCL_SYNC=keep     module default, synchronous

Worth running the ladder under `0` *and* `keep` if allocation allows — the gap
between them is itself a result, and it is the one number that says how much the
site's own default is costing. They answer different questions, so label which
is which; `run_metadata.txt` records `ccl_sync_mode=`.

The override lives in `bin/tc-perf-env` and nowhere else: `tc-perf-run` loads
the frameworks module, which re-sets both to 1, so an export in `run.sh` or a
job script is silently undone before the ranks start.

`DRY=1` launches no MPI, but it is **not instant**: `tc-perf-run` probes
`import torch` before it looks at `--dry-run`, and that import costs ~17 s off
Lustre — every invocation, dry or not. A dry full ladder is ~48 × 19 s ≈ 15 min.
Dry-run one config to check a command line; don't dry-run the whole ladder.

## Know the cost before you commit the allocation

`run.sh` prints a launch count in its banner. **Read it.** `tc-perf-run` calls
`mpiexec` once *per adapter*, so the defaults come to

    REPEATS 2 x NODES 3 x RPN 2 x COLLECTIVES 4 = 48 configs, x3 adapters = 144 launches

and each launch pays torch + oneCCL init on every rank before it measures
anything. That startup tax, not the measurement, is what fills a 6-hour
walltime. To fit a smaller window cut collectives first — they multiply.

## If something looks wrong

| Symptom | Cause |
|---|---|
| No output at all, instant exit | Lmod + `set -u`. Never redirect stderr away. |
| `No module named 'torchcomms._comms'` | A torchcomms clone is on `PYTHONPATH`. Remove it. |
| Ranks hang at startup | `MASTER_ADDR` differs per rank. Check `run_metadata.txt`. |
| `site=generic` in the banner | Detection missed. Export `TCPERF_SITE=sunspot`. |

The banner line prints `site=` on every run — glance at it. It should say
`sunspot`, and `run.sh` exports that explicitly, so it should never say
`generic`.

## Where things land

    results/<run-id>/run_metadata.txt    read this before trusting any number
    results/<run-id>/<adapter>/*.csv
    logs/<run-id>_<adapter>.log

## Batch — beyond the 4-node interactive allocation

`jobs/sunspot.pbs` is already written. Submit **from the repo root** (it finds
the repo through `$PBS_O_WORKDIR`):

    qsub jobs/sunspot.pbs                                    # select=4, 6h, ladder
    qsub -l select=8 -l walltime=08:00:00 jobs/sunspot.pbs   # bigger rung
    qsub -v STAGES="preflight smoke check" jobs/sunspot.pbs   # short shakedown

The qsub command line overrides the directives in the file, so one job file
covers every node count — no need to copy it per scale.

`-v` passes knobs through. PBS splits that list on **commas**, so a value may
contain spaces but never a comma:

    qsub -v STAGES="preflight ladder",REPEATS=3 jobs/sunspot.pbs
    qsub -v COLLECTIVES="all_reduce all_to_all_single" jobs/sunspot.pbs

Going past 4 nodes: add the rung to `NODE_RUNGS` as well as to `select`, or the
extra nodes sit idle —

    qsub -l select=16 -v NODE_RUNGS="4 8 16" jobs/sunspot.pbs

Note: `jobs/smoke.pbs` and `jobs/sweep.pbs` predate this and carry **Aurora**
values (`-q debug`/`prod`, `filesystems=home:flare`). Do not qsub them on
Sunspot as-is.
