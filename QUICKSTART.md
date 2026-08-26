# QUICKSTART — Sunspot interactive session

Everything you need is in this repo. Nothing to install, nothing to fetch.

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
    DRY=1                      bash run.sh ladder    # print commands, launch nothing

`DRY=1` is free and launches nothing — use it to see exactly what would run.

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

## Batch, later

Prepend to `run.sh` (directives go at the top, under the shebang):

    #PBS -N tcperf-ladder
    #PBS -l select=4
    #PBS -l walltime=06:00:00
    #PBS -l filesystems=home:tegu
    #PBS -q workq
    #PBS -A datascience
    #PBS -j oe

then `cd "$PBS_O_WORKDIR"` and set `STAGES="preflight ladder"`.

Note: `jobs/smoke.pbs` and `jobs/sweep.pbs` carry **Aurora** values
(`-q debug`/`prod`, `filesystems=home:flare`). Do not qsub them on Sunspot
as-is.
