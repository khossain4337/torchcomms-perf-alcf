#!/bin/bash
# push-to-sunspot.sh — rsync this repo to Sunspot. Run from the flare side.
#
#     bash push-to-sunspot.sh            # dry run, shows what would transfer
#     bash push-to-sunspot.sh --go       # actually transfer
#
# Override the destination if these guesses are wrong:
#     DEST_HOST=sunspot.alcf.anl.gov DEST_PATH=/some/where bash push-to-sunspot.sh --go
#
# PULLING FROM SUNSPOT INSTEAD works just as well, and avoids needing an
# outbound login from the flare side. Same excludes, direction reversed:
#
#     rsync -av \
#       --exclude 'results/' --exclude 'logs/' --exclude '.cache/' \
#       --exclude '__pycache__/' --exclude '*.pyc' --exclude 'perf_standalone.bak.*/' \
#       <flare-host>:/lus/flare/projects/datasets/softwares/testing/torchcomm_example/torchcomms-perf-alcf/ \
#       /lus/tegu/projects/datasets/software/testing/torchcomm_example/torchcomms-perf-alcf/
#
# The excludes matter in both directions: .cache/ is a full torchcomms clone
# (tens of MB) that the Sunspot side never needs, and results/ is per-machine,
# so copying it across only muddles a later comparison. Note the trailing
# slashes -- `src/` copies the contents, `src` copies the directory into dest.

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
# .git/ is also included, deliberately. `du` makes it look like half the repo
# (496 KB) but that is 4 KB of block per tiny loose object -- the real content
# is 84 KB across 65 files. Including it costs ~27% more bytes and makes the
# Sunspot copy a real repo, so a fix made there while staring at a failure can
# be committed and pulled back instead of retyped. NOGIT=1 drops it.
#
#   with .git : 122 files, 395 KB
#   NOGIT=1   :  59 files, 311 KB
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
[ "${NOGIT:-0}" = "1" ] && EXCLUDES+=(--exclude '.git/')

# -a preserves the execute bits; without them ./run.sh would need a chmod on the
# far side (though `bash run.sh` works regardless).
FLAGS=(-av --human-readable)
[ "$GO" = "0" ] && FLAGS+=(--dry-run)

# ALCF logins offer many keys and the server drops the connection after a few
# ("Too many authentication failures"). RSH lets you pin one.
[ -n "${RSH:-}" ] && FLAGS+=(-e "$RSH")

echo "[push] from : $REPO/"
echo "[push] to   : ${DEST_HOST}:${DEST_PATH}/"
echo "[push] git  : $([ "${NOGIT:-0}" = "1" ] && echo "excluded (NOGIT=1)" || echo "included (84 KB of objects)")"
[ "$GO" = "0" ] && echo "[push] DRY RUN — pass --go to transfer for real"
echo

# rsync creates the destination path happily, so a typo in DEST_PATH does not
# fail -- it silently seeds a second copy of the repo in the wrong place, which
# you then run and get confused by. Check the parent exists before writing.
if [ "$GO" = "1" ]; then
    parent="$(dirname "$DEST_PATH")"
    if ! ssh -o BatchMode=yes "$DEST_HOST" "test -d '$parent'" 2>/dev/null; then
        echo "[push] WARNING: ${DEST_HOST}:${parent} is not a directory we can see."
        echo "[push]          Either the path is wrong or ssh needs a password."
        echo "[push]          Continuing -- rsync will report the real error."
        echo
    fi
fi

rsync "${FLAGS[@]}" "${EXCLUDES[@]}" "$REPO/" "${DEST_HOST}:${DEST_PATH}/"
rc=$?

echo
if [ "$rc" -ne 0 ]; then
    echo "[push] rsync failed (rc=$rc)."
    echo
    echo "[push] 'Too many authentication failures' means ssh offered every key in"
    echo "[push] your agent and the server cut it off before reaching the right one."
    echo "[push] It is not a wrong path. Pin the identity:"
    echo
    echo "[push]     rsync -e 'ssh -o IdentitiesOnly=yes -i ~/.ssh/<key>' ..."
    echo "[push]     RSH=\"ssh -o IdentitiesOnly=yes -i ~/.ssh/<key>\" bash push-to-sunspot.sh --go"
    echo
    echo "[push] ALCF logins also want a MobilePASS+ passcode, which needs a terminal --"
    echo "[push] run this yourself rather than from anything non-interactive."
    echo "[push] If the host or path is wrong instead, set DEST_HOST / DEST_PATH."
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
