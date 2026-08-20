#!/bin/bash
# sites/common.sh — site detection and shared defaults.
#
# Sourced by every bin/tc-perf-* script. Selects a site profile from
# sites/<name>.sh, either from $TCPERF_SITE or by sniffing the hostname.
#
# A site profile is expected to set (or leave at the default):
#   TCPERF_HSN_SUFFIX      suffix appended to a bare nodename to reach it over
#                          the high-speed network (empty = use the name as-is)
#   TCPERF_TILES_PER_NODE  accelerators visible per node with the hierarchy
#                          setting below (12 on PVC with FLAT)
#   TCPERF_DEFAULT_RPN     ranks per node when the caller does not say
#   TCPERF_MODULE_LOAD     shell snippet that makes `python -c "import torch"`
#                          work; run with `set +u` (see the Lmod note in
#                          tcperf_load_env)
#   TEST_BACKEND / TEST_DEVICE and any CCL_*/ZE_* defaults
#
# Nothing here may hardcode a hostname: that is what the site files are for.

# --- locate the repo --------------------------------------------------------
# BASH_SOURCE[0] is this file; the repo root is its parent's parent.
TCPERF_ROOT="${TCPERF_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export TCPERF_ROOT

# --- site detection ---------------------------------------------------------
tcperf_detect_site() {
    if [ -n "${TCPERF_SITE:-}" ]; then
        echo "$TCPERF_SITE"; return
    fi
    local fqdn
    fqdn="$(hostname -f 2>/dev/null || hostname)"
    case "$fqdn" in
        *.sunspot.alcf.anl.gov|sunspot-*) echo sunspot ;;
        *.aurora.alcf.anl.gov|aurora-*|x4*) echo aurora ;;
        *) echo generic ;;
    esac
}

# --- defaults, overridable by the site profile ------------------------------
: "${TCPERF_HSN_SUFFIX:=}"
: "${TCPERF_TILES_PER_NODE:=12}"
: "${TCPERF_DEFAULT_RPN:=12}"
: "${TCPERF_MASTER_PORT:=29500}"

TCPERF_SITE="$(tcperf_detect_site)"
export TCPERF_SITE

_tcperf_profile="$TCPERF_ROOT/sites/${TCPERF_SITE}.sh"
if [ -r "$_tcperf_profile" ]; then
    # shellcheck source=/dev/null
    . "$_tcperf_profile"
else
    echo "tc-perf: warning: no site profile for '$TCPERF_SITE' ($_tcperf_profile)" >&2
    echo "tc-perf:          continuing with generic defaults; set TCPERF_SITE to override" >&2
fi

# --- helpers ----------------------------------------------------------------

# Turn a bare nodename into something every rank can reach. Never call this
# with `hostname` from inside a per-rank wrapper: each rank would elect itself
# as master. Derive it once, in the outer job script, from PBS_NODEFILE.
tcperf_reachable() {
    local h="$1"
    case "$h" in
        *.*) echo "$h" ;;                       # already qualified
        *)   echo "${h}${TCPERF_HSN_SUFFIX}" ;;
    esac
}

# Node count and master address from the PBS allocation.
# Sets NNODES and MASTER_ADDR. Falls back to a single local node off-allocation
# so `tc-perf-doctor` and dry runs work on a login node.
tcperf_topology() {
    if [ -n "${PBS_NODEFILE:-}" ] && [ -r "${PBS_NODEFILE}" ]; then
        NNODES=$(wc -l < "$PBS_NODEFILE")
        MASTER_ADDR="$(tcperf_reachable "$(head -n 1 "$PBS_NODEFILE")")"
    else
        NNODES=1
        MASTER_ADDR="$(tcperf_reachable "$(hostname)")"
        echo "tc-perf: note: no PBS_NODEFILE; assuming 1 node ($MASTER_ADDR)" >&2
    fi
    export NNODES MASTER_ADDR
}

# Make the frameworks environment available.
#
# CRITICAL: Lmod's `module` is a shell function whose generated code references
# $ZSH_EVAL_CONTEXT, which does not exist in bash. Under `set -u` that is an
# unbound-variable error that kills the calling script outright — and if its
# stderr is redirected, it dies with no output at all. This cost us an
# afternoon. Hence `set +u` around the call, and never swallow its stderr.
tcperf_load_env() {
    if [ "${TCPERF_SKIP_MODULE:-0}" = "1" ]; then
        echo "tc-perf: TCPERF_SKIP_MODULE=1, leaving the environment alone" >&2
        return 0
    fi
    if python -c "import torch" 2>/dev/null; then
        echo "tc-perf: torch already importable, skipping module load" >&2
        return 0
    fi
    if [ -z "${TCPERF_MODULE_LOAD:-}" ]; then
        echo "tc-perf: warning: no TCPERF_MODULE_LOAD for site '$TCPERF_SITE'" >&2
        return 0
    fi
    set +u                              # <-- see note above
    eval "$TCPERF_MODULE_LOAD" || echo "tc-perf: warning: module load reported failure" >&2
    set -u
}

tcperf_die() { echo "tc-perf: $*" >&2; exit 1; }
