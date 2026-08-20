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
# and --sync-interval report nearly the same thing. We deliberately do NOT
# override them — the defaults are what users actually run under — but any
# async-vs-sync comparison must say so. See docs/METHODOLOGY.md.
