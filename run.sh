#!/bin/bash
# run.sh — drive a torchcomms collective-perf session on an ALCF PVC machine.
#
# Written to be run INTERACTIVELY first:
#
#     qsub -I -l select=4 -l walltime=6:00:00 -q workq \
#          -l filesystems=home:tegu -A datascience
#     cd <this repo>
#     ./run.sh preflight        # ~1 min   doctor only, no MPI
#     ./run.sh smoke            # ~3 min   all 3 adapters, tiny sizes
#     ./run.sh ladder           # ~30 min  scale ladder, the real first data
#
# and then converted to batch by prepending PBS directives (see BATCH below).
# The stages are deliberately separate: each answers a question you want
# answered before spending time on the next one.
#
#     preflight  is the environment sane? (no allocation time wasted on MPI)
#     smoke      does the pipe connect, all three adapters, on THIS machine?
#     check      do the three adapters actually report different numbers?
#     ladder     first real data: scale across nodes and ranks-per-node
#     sweep      the long one: many collectives, full size range, repeats
#
# Knobs (all env-overridable):
#     STAGES="smoke ladder"     ./run.sh            # same as passing them as args
#     COLLECTIVES="all_reduce"  ./run.sh ladder
#     REPEATS=3                 ./run.sh sweep
#     NODE_RUNGS="1 2 4"        ./run.sh ladder
#     RPN_RUNGS="2 12"          ./run.sh ladder
#     DRY=1                     ./run.sh ladder     # print commands, launch nothing

set -uo pipefail   # NOT -e: a failing rung must not abandon the rest of the run

# Echo before anything else can fail, so "no output at all" always means
# "never started" rather than "died early and quietly" (see the Lmod trap).
echo "[run.sh] start $(date -Is) on $(hostname)"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO"

# --- site -------------------------------------------------------------------
# Export it rather than trusting detection. sites/common.sh CAN work this out
# (cabinet prefix x1*->sunspot, x4*->aurora), but those prefixes are observed,
# not documented, and the failure mode when detection is wrong is quiet: the
# `generic` profile has an empty HSN suffix and 1 tile/node, so a multi-node
# run either fails to rendezvous or measures one rank per node and says nothing.
# Being explicit costs one line.
export TCPERF_SITE="${TCPERF_SITE:-sunspot}"

# --- what to run ------------------------------------------------------------
STAGES="${STAGES:-}"
[ $# -gt 0 ] && STAGES="$*"
[ -z "$STAGES" ] && STAGES="preflight smoke"

# Four collectives spanning the communication patterns that matter:
#   all_reduce             the one everybody quotes; reduction + broadcast
#   all_gather_single      pure gather, no reduction arithmetic
#   reduce_scatter_single  the all_reduce halves, separately
#   all_to_all_single      the one that actually stresses the fabric bisection
COLLECTIVES="${COLLECTIVES:-all_reduce all_gather_single reduce_scatter_single all_to_all_single}"

# Scale ladder. Each rung catches something the others cannot:
#   1 node   intra-node only: tile-to-tile over the on-package fabric
#   2 nodes  the first rung with ANY inter-node traffic
#   4 nodes  the first rung where inter-node cost can be seen to SCALE --
#            two points make a line, three tell you whether it is one
NODE_RUNGS="${NODE_RUNGS:-1 2 4}"
#   2 rpn    partial-node: the layout where the pre-patch device-binding bug
#            was WRONG, so this rung regression-tests patch 0001
#   12 rpn   full node, all tiles busy: the configuration people actually run
RPN_RUNGS="${RPN_RUNGS:-2 12}"

REPEATS="${REPEATS:-2}"        # >=2, always: one run says nothing about noise
DRY="${DRY:-0}"

# --- allocation -------------------------------------------------------------
if [ -n "${PBS_NODEFILE:-}" ] && [ -r "${PBS_NODEFILE}" ]; then
    ALLOC_NODES=$(wc -l < "$PBS_NODEFILE")
else
    ALLOC_NODES=1
    echo "[run.sh] note: no PBS_NODEFILE -- assuming 1 node (login node?)"
fi

echo "[run.sh] site=$TCPERF_SITE  allocation=${ALLOC_NODES} node(s)  stages: $STAGES"
echo

# tc-perf-run takes its node count from PBS_NODEFILE (the whole allocation) and
# has no --nodes flag. To run a 2-node rung inside a 4-node allocation we hand
# it a TRUNCATED nodefile. Writing it into the results tree keeps it with the
# data that it explains, and out of any shared or transient directory.
NODEFILE_DIR="$REPO/results/.nodefiles"
mkdir -p "$NODEFILE_DIR"

# Dry runs write their metadata here instead of into results/, so a --dry-run
# never leaves anything that could later be mistaken for a real (but empty) run.
DRY_OUTBASE="$REPO/results/.dryrun"
[ "$DRY" = "1" ] && { rm -rf "$DRY_OUTBASE"; mkdir -p "$DRY_OUTBASE"; }

# Count what actually ran, so "the ladder finished" cannot quietly mean "every
# rung was skipped" -- e.g. a typo'd NODE_RUNGS, or a smaller allocation than
# the one the rungs were written for.
RUNGS_RUN=0
RUNGS_SKIPPED=0

# Run one configuration. Args: <nodes> <rpn> <collective> <tag> [extra...]
run_one() {
    local nodes="$1" rpn="$2" coll="$3" tag="$4"; shift 4

    if [ "$nodes" -gt "$ALLOC_NODES" ]; then
        echo "  SKIP  ${nodes}n x ${rpn}rpn $coll -- allocation has only $ALLOC_NODES node(s)"
        RUNGS_SKIPPED=$((RUNGS_SKIPPED+1))
        return 0
    fi
    RUNGS_RUN=$((RUNGS_RUN+1))

    # Hand tc-perf-run a truncated nodefile for a sub-allocation rung. That is
    # what sets NNODES (hence NRANKS = NNODES*RPN) and MASTER_ADDR, both of
    # which tc-perf-run reads from PBS_NODEFILE and nowhere else.
    #
    # Placement follows regardless: `mpiexec -n 24 -ppn 12` fills the first two
    # nodes of the allocation by default, so the truncation and the launcher
    # agree without needing --hosts. Worth an eyeball on the first real
    # multi-rung run -- check `nodes=` in run_metadata.txt against the rank
    # count actually reported in the CSV's Ranks column.
    local env_pfx=(env)
    if [ -n "${PBS_NODEFILE:-}" ] && [ "$nodes" -lt "$ALLOC_NODES" ]; then
        local nf="$NODEFILE_DIR/nodes.$nodes"
        head -n "$nodes" "$PBS_NODEFILE" > "$nf"
        env_pfx+=("PBS_NODEFILE=$nf")
    fi

    local dry=()
    if [ "$DRY" = "1" ]; then
        dry=(--dry-run)
        # tc-perf-run mkdirs its output tree and writes run_metadata.txt before
        # it checks --dry-run, so a dry run would otherwise scatter empty
        # result dirs through results/ that look exactly like real runs with
        # missing CSVs. Redirect them somewhere disposable.
        env_pfx+=("OUTBASE=$DRY_OUTBASE/${tag}_N${nodes}_R${rpn}_${coll}")
    fi

    echo "  RUN   ${nodes}n x ${rpn}rpn  $coll  [$tag]"
    "${env_pfx[@]}" "$REPO/bin/tc-perf-run" \
        --rpn "$rpn" \
        --collective "$coll" \
        --tag "$tag" \
        "${dry[@]}" \
        "$@"
    local rc=$?
    [ "$rc" -ne 0 ] && echo "  ^^ rc=$rc (continuing)"
    return 0
}

# --- stages -----------------------------------------------------------------
for stage in $STAGES; do
echo "=============================================================="
echo "STAGE: $stage"
echo "=============================================================="

case "$stage" in

preflight)
    # No MPI, no allocation time at risk. Non-zero exit means a FAIL check,
    # which is worth stopping for -- but this script does not stop on your
    # behalf, it just says so loudly.
    "$REPO/bin/tc-perf-doctor"
    rc=$?
    echo
    if [ "$rc" -ne 0 ]; then
        echo "[run.sh] doctor reported FAILures. Read them before running anything else."
    else
        echo "[run.sh] doctor is green."
    fi
    ;;

smoke)
    # Tiny, all three adapters, 2 ranks on 1 node. Proves the pipe connects on
    # this machine, this module, this site profile. Not a measurement.
    run_one 1 2 all_reduce smoke --min-size 1024 --max-size 4096 \
                                 --iters 20 --warmup 2 --sync-interval 0
    ;;

check)
    # The question nobody has answered yet: do the three adapters actually
    # report DIFFERENT numbers? If they are identical to the microsecond, the
    # adapter switch is not taking effect and every comparison downstream is
    # meaningless. Cheap to ask, and it invalidates everything if it fails.
    latest=$(ls -1dt "$REPO"/results/smoke_* 2>/dev/null | head -1)
    if [ -z "$latest" ]; then
        echo "  no smoke results yet -- run './run.sh smoke' first"
    else
        echo "  comparing adapters in: $latest"
        echo
        for a in torchcomms c10d c10d_torchcomms; do
            f="$latest/$a/all_reduce.csv"
            if [ -r "$f" ]; then
                # fields: 4=SendMsgSize(B) 5=Ranks 10=LatAvg(us)
                printf '  %-18s ' "$a"
                awk -F, 'NR>1 {printf "%s:%s  ", $4, $10}' "$f"
                echo
            else
                printf '  %-18s (no csv)\n' "$a"
            fi
        done
        echo
        echo "  Identical to the microsecond across all three => investigate before"
        echo "  trusting any comparison. Some difference => the switch is live."
    fi
    ;;

ladder)
    # First real data. One collective by default is the wrong instinct here:
    # the point of the ladder is scaling behaviour, and all_reduce alone can
    # look fine while all_to_all_single falls off a cliff at the same rung.
    for rep in $(seq 1 "$REPEATS"); do
        for nodes in $NODE_RUNGS; do
            for rpn in $RPN_RUNGS; do
                for coll in $COLLECTIVES; do
                    run_one "$nodes" "$rpn" "$coll" "ladder-rep${rep}" \
                        --min-size 1024 --max-size 16777216 \
                        --iters 100 --warmup 50 --sync-interval 1
                done
            done
        done
    done
    ;;

sweep)
    # The long one. Full 64 MiB range, every collective in $COLLECTIVES, at
    # the largest rung the allocation allows. Hours, not minutes.
    for rep in $(seq 1 "$REPEATS"); do
        for rpn in $RPN_RUNGS; do
            for coll in $COLLECTIVES; do
                run_one "$ALLOC_NODES" "$rpn" "$coll" "sweep-rep${rep}" \
                    --min-size 1024 --max-size 67108864 \
                    --iters 100 --warmup 50 --sync-interval 1
            done
        done
    done
    ;;

analyze)
    # No torch, no MPI, no GPU -- runs anywhere, including off-node later.
    shopt -s nullglob
    dirs=("$REPO"/results/ladder-rep*/ "$REPO"/results/sweep-rep*/)
    shopt -u nullglob
    if [ ${#dirs[@]} -eq 0 ]; then
        echo "  nothing to analyze yet"
    else
        for d in "${dirs[@]}"; do
            echo "  --- $d"
            "$REPO/bin/tc-perf-analyze" "$d" --baseline c10d || echo "  (analyze rc=$?)"
        done
    fi
    ;;

*)
    echo "  unknown stage '$stage'"
    echo "  known: preflight smoke check ladder sweep analyze"
    ;;
esac
echo
done

echo "=============================================================="
echo "[run.sh] done $(date -Is)"
if [ "$((RUNGS_RUN + RUNGS_SKIPPED))" -gt 0 ]; then
    echo "  rungs   : $RUNGS_RUN run, $RUNGS_SKIPPED skipped"
    if [ "$RUNGS_RUN" -eq 0 ]; then
        echo "  !! EVERY rung was skipped -- no data was produced."
        echo "  !! NODE_RUNGS='$NODE_RUNGS' vs an allocation of $ALLOC_NODES node(s)."
    fi
fi
echo "  results : $REPO/results/"
echo "  logs    : $REPO/logs/"
echo
echo "Next:  ./run.sh check      # are the three adapters actually different?"
echo "       ./run.sh analyze    # plots + regression reports"
echo "=============================================================="

# --- BATCH ------------------------------------------------------------------
# To convert this to a qsub script, prepend directives ABOVE the shebang line's
# neighbours -- PBS reads them from the top of the file, before the first
# non-comment line -- and pick the stages via the STAGES env var:
#
#     #!/bin/bash
#     #PBS -N tcperf-ladder
#     #PBS -l select=4
#     #PBS -l walltime=06:00:00
#     #PBS -l filesystems=home:tegu
#     #PBS -q workq
#     #PBS -A datascience
#     #PBS -j oe
#     cd "$PBS_O_WORKDIR"
#     STAGES="preflight ladder" ./run.sh
#
# Note that jobs/smoke.pbs and jobs/sweep.pbs in this repo carry AURORA values
# (-q debug/prod, -l filesystems=home:flare). They are not right for Sunspot as
# written; this file's directives above are.
