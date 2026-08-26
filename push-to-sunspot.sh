#!/bin/bash
# push-to-sunspot.sh — rsync this repo to Sunspot. Run from the flare side.
#
#     bash push-to-sunspot.sh            # dry run, shows what would transfer
#     bash push-to-sunspot.sh --go       # actually transfer
#
# Override the destination if these guesses are wrong:
#     DEST_HOST=sunspot.alcf.anl.gov DEST_PATH=/some/where bash push-to-sunspot.sh --go

set -uo pipefail
echo "[push] start $(date -Is)"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DEST_HOST="${DEST_HOST:-sunspot.alcf.anl.gov}"
DEST_PATH="${DEST_PATH:-/lus/tegu/projects/datasets/software/testing/torchcomm_example/torchcomms-perf-alcf}"

GO=0
[ "${1:-}" = "--go" ] && GO=1

# perf_standalone/ IS included on purpose: it is the built, patched harness, and
# shipping it is exactly why Sunspot needs no clone, no network, and no setup
# step. It is gitignored (generated), but that says nothing about rsync.
#
# Excluded: run output, which is per-machine and would only confuse a later
# comparison, and .cache/ which is a full torchcomms clone we do not need there.
EXCLUDES=(
    --exclude 'results/'
    --exclude 'logs/'
    --exclude '.cache/'
    --exclude '__pycache__/'
    --exclude '*.pyc'
    --exclude 'perf_standalone.bak.*/'
)

# -a preserves the execute bits; without them ./run.sh would need a chmod on the
# far side (though `bash run.sh` works regardless).
FLAGS=(-av --human-readable)
[ "$GO" = "0" ] && FLAGS+=(--dry-run)

echo "[push] from : $REPO/"
echo "[push] to   : ${DEST_HOST}:${DEST_PATH}/"
[ "$GO" = "0" ] && echo "[push] DRY RUN — pass --go to transfer for real"
echo

rsync "${FLAGS[@]}" "${EXCLUDES[@]}" "$REPO/" "${DEST_HOST}:${DEST_PATH}/"
rc=$?

echo
if [ "$rc" -ne 0 ]; then
    echo "[push] rsync failed (rc=$rc)."
    echo "[push] If the host or path is wrong, set DEST_HOST / DEST_PATH and retry."
    exit "$rc"
fi

if [ "$GO" = "0" ]; then
    echo "[push] dry run OK. Re-run with --go to transfer."
else
    cat <<EOF
[push] done. On Sunspot:

    cd $DEST_PATH
    ml add frameworks
    bash run.sh preflight

See QUICKSTART.md there for the rest.
EOF
fi
