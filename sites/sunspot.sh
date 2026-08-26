#!/bin/bash
# sites/sunspot.sh — ALCF Sunspot (PVC, PBS + PALS/PMIx).
#
# Values here are the ones we actually verified on Sunspot in Aug 2026, taken
# from the working run_integration_test.sh / test1_job_script.sh. Change them
# here, not in bin/.

# Bare nodenames from PBS_NODEFILE are not routable over the HSN without this.
TCPERF_HSN_SUFFIX="-hsn0.hsn.cm.sunspot.alcf.anl.gov"

# 6 PVC cards x 2 tiles, with ZE_FLAT_DEVICE_HIERARCHY=FLAT below.
TCPERF_TILES_PER_NODE=12
TCPERF_DEFAULT_RPN=12

# Bringing up the frameworks conda env. Evaluated under `set +u`.
# Override with TCPERF_MODULE_LOAD from the job script to pin a different RC.
TCPERF_MODULE_LOAD='module add frameworks'

# --- harness knobs ----------------------------------------------------------
export TEST_BACKEND="${TEST_BACKEND:-xccl}"
export TEST_DEVICE="${TEST_DEVICE:-xpu}"

# --- Level Zero / oneCCL ----------------------------------------------------
# FLAT exposes each tile as its own device (12/node). Changing this changes
# what "a rank" means, so it belongs in the site profile, not in bin/.
export ZE_FLAT_DEVICE_HIERARCHY="${ZE_FLAT_DEVICE_HIERARCHY:-FLAT}"
export CCL_ATL_TRANSPORT="${CCL_ATL_TRANSPORT:-mpi}"
export CCL_KVS_MODE="${CCL_KVS_MODE:-pmi}"
export CCL_PROCESS_LAUNCHER="${CCL_PROCESS_LAUNCHER:-pmix}"

# NOTE (measurement confound): the frameworks module ships CCL_ATL_SYNC_COLL=1
# and CCL_OP_SYNC=1. Those force synchronous collectives, which makes --async
# and --sync-interval report nearly the same thing.
#
# We now DO override them, to 0, in bin/tc-perf-env — see the block there for
# why that is the only place it can go (this profile is sourced before the
# module load re-sets them). TCPERF_CCL_SYNC=keep restores the module default
# if you want the as-users-run-it number; `unset` removes them entirely.
#
# The override is not free of consequence: 0 measures the library's own
# asynchrony, `keep` measures what someone gets by loading the module and
# running. Both are legitimate, they are not the same question, and a report
# must say which one it used. run_metadata.txt records it as ccl_sync_mode=.
# See docs/METHODOLOGY.md.
