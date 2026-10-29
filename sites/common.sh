#!/bin/bash
# sites/common.sh — site detection and shared defaults.
#
# Sourced by every bin/tc-perf-* script. Selects a site profile from
# sites/<name>.sh, either from $TCPERF_SITE or by sniffing the hostname.
#
# A site profile is expected to set (or leave at the default):
#   TCPERF_HSN_SUFFIX      suffix appended to a bare nodename to reach it over
#                          the high-speed network (empty = use the name as-is).
#                          NOT used for rendezvous -- see the next entry.
#   TCPERF_RDZV_SUFFIX     suffix for the MASTER_ADDR rendezvous address.
#                          Defaults to TCPERF_HSN_SUFFIX, which is wrong on
#                          Sunspot and Aurora: those profiles set it to the
#                          management network. Rendezvous is a control-plane
#                          TCP handshake, not a data path.
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
    local fqdn short
    fqdn="$(hostname -f 2>/dev/null || hostname)"
    short="${fqdn%%.*}"

    # 1. A qualified name settles it outright. Login nodes answer this way.
    case "$fqdn" in
        *.sunspot.alcf.anl.gov|sunspot-*) echo sunspot; return ;;
        *.aurora.alcf.anl.gov|aurora-*)   echo aurora;  return ;;
    esac

    # 2. COMPUTE nodes do not: they answer with a bare cabinet name and no
    #    domain at all, so step 1 misses every one of them. That is how this
    #    used to land on `generic` — which carries an EMPTY HSN suffix and
    #    1 tile/node, i.e. a silently broken multi-node run. tc-perf-run and
    #    tc-perf-env both detect the site on a compute node, so this is the
    #    normal path, not an edge case.
    #
    #    Cabinet prefixes OBSERVED so far: Sunspot x1921*, Aurora x4305*.
    #    That is the whole basis for the two rules below — it is a heuristic,
    #    not a documented guarantee, and a prefix collision would send a run to
    #    the wrong HSN domain. Two things keep that cheap: step 3 catches any
    #    prefix we have no rule for, and the job script should export
    #    TCPERF_SITE anyway (step 0), which makes detection a safety net rather
    #    than the mechanism. Deliberately no DNS here: tc-perf-env sources this
    #    once per rank, and a lookup per rank is a DNS storm at job start.
    case "$short" in
        x1*) echo sunspot; return ;;
        x4*) echo aurora;  return ;;
    esac

    # 3. An ALCF-shaped name with a cabinet prefix we have no rule for: ask DNS
    #    which machine claims its HSN address. Definitive when it answers.
    #    Gated on the x<digit> shape so an unknown host never pays a DNS
    #    timeout just to be told it is `generic`.
    case "$short" in
        x[0-9]*)
            local m
            for m in sunspot aurora; do
                if getent hosts "${short}-hsn0.hsn.cm.${m}.alcf.anl.gov" >/dev/null 2>&1; then
                    echo "$m"; return
                fi
            done ;;
    esac

    echo generic
}

# --- defaults, overridable by the site profile ------------------------------
: "${TCPERF_HSN_SUFFIX:=}"
: "${TCPERF_TILES_PER_NODE:=12}"
: "${TCPERF_DEFAULT_RPN:=12}"
: "${TCPERF_MASTER_PORT:=29500}"

# Remember whether the caller chose the site or we guessed it — the generic
# warning below fires only on a guess.
TCPERF_SITE_EXPLICIT="${TCPERF_SITE:+1}"
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

# Rendezvous suffix defaults to the HSN one, so a site profile written before
# this distinction existed keeps its old behaviour instead of silently losing
# its suffix. MUST come after the profile is sourced, or the profile's own
# TCPERF_RDZV_SUFFIX would be clobbered.
: "${TCPERF_RDZV_SUFFIX:=$TCPERF_HSN_SUFFIX}"

# Falling back to `generic` used to be SILENT, because sites/generic.sh exists
# and is readable — so the branch above had nothing to complain about. But
# generic carries an empty HSN suffix and 1 tile/node: a multi-node run under
# it either fails to rendezvous or quietly measures one rank per node. Say so.
# Only when generic was *guessed*: TCPERF_SITE=generic is a deliberate choice.
if [ "$TCPERF_SITE" = generic ] && [ -z "${TCPERF_SITE_EXPLICIT:-}" ]; then
    echo "tc-perf: warning: site detected as 'generic' on $(hostname) — no HSN suffix," >&2
    echo "tc-perf:          ${TCPERF_TILES_PER_NODE} tile(s)/node. Multi-node runs will misbehave." >&2
    echo "tc-perf:          Export TCPERF_SITE=sunspot (or aurora) if that is wrong." >&2
fi

# --- helpers ----------------------------------------------------------------

# Turn a nodefile entry into a rendezvous address every rank can reach. Never
# call this with `hostname` from inside a per-rank wrapper: each rank would
# elect itself as master. Derive it once, from PBS_NODEFILE.
#
# STRIP FIRST, THEN APPEND. PBS_NODEFILE on Sunspot does not hold bare
# nodenames -- it holds names that are ALREADY qualified, and already point at
# the fabric interface:
#
#     x1921c1s0b0n0-hsn0.hsn.cm.sunspot.alcf.anl.gov
#
# The old body passed those straight through on the `*.*` branch. That never
# produced a doubled name, so it looked correct -- but it handed back the -hsn0
# address, and rendezvous on -hsn0 is exactly the failure this function has to
# avoid. See TCPERF_RDZV_SUFFIX in the site profile for why.
#
# Cutting at the first dot and dropping -hsn0 recovers the bare nodename, which
# makes the result identical whether the nodefile is qualified or not -- so a
# site whose nodefile holds bare names is unaffected.
tcperf_reachable() {
    local h="$1" n

    # No suffix configured (sites/generic.sh) means we have nothing better to
    # offer than the name we were handed -- so hand it back whole. Stripping
    # here would turn a perfectly good qualified nodefile entry into a bare
    # name that may not resolve.
    [ -z "${TCPERF_RDZV_SUFFIX:-}" ] && { echo "$h"; return; }

    n="${h%%.*}"                                # drop any domain PBS added
    n="${n%-hsn0}"                              # and the fabric-interface tag
    echo "${n}${TCPERF_RDZV_SUFFIX}"
}

# Node count and master address from the PBS allocation.
# Sets NNODES and MASTER_ADDR. Falls back to a single local node off-allocation
# so `tc-perf-doctor` and dry runs work on a login node.
tcperf_topology() {
    local name ip
    if [ -n "${PBS_NODEFILE:-}" ] && [ -r "${PBS_NODEFILE}" ]; then
        NNODES=$(wc -l < "$PBS_NODEFILE")
        name="$(tcperf_reachable "$(head -n 1 "$PBS_NODEFILE")")"
    else
        NNODES=1
        name="$(tcperf_reachable "$(hostname)")"
        echo "tc-perf: note: no PBS_NODEFILE; assuming 1 node ($name)" >&2
    fi
    # Resolve once here so ranks never hit DNS at scale; a multi-homed name
    # (Aurora bare .hsn: 8 A records) is pinned to its first address. Keeps the
    # name if it does not resolve, so --dry-run still works on a login node.
    ip="$(getent hosts "$name" | awk '{print $1; exit}')"
    MASTER_ADDR="${ip:-$name}"
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
