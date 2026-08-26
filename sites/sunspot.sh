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

# --- CPU / worker / device affinity -----------------------------------------
# Sunspot node: 2 sockets x 52 cores, 6 PVC cards x 2 tiles. Left unpinned, the
# kernel migrates ranks across sockets mid-run and the numbers acquire a spread
# that has nothing to do with the collective.
#
# CPU_AFFINITY is consumed by the LAUNCHER, not by a rank: bin/tc-perf-run
# passes it as `mpiexec --cpu-bind "$CPU_AFFINITY"`. PALS `list:` maps the Nth
# colon-separated group onto LOCAL rank N, so the ordering here is the rank ->
# core-set mapping. 12 groups, one per tile, first six on socket 0 and last six
# on socket 1 -- matching the tile ordering FLAT produces.
export CPU_AFFINITY="${CPU_AFFINITY:-list:4-7:8-11:12-15:16-19:20-23:24-27:56-59:60-63:64-67:68-71:72-75:76-79}"

# oneCCL's own progress threads, one per rank, pinned clear of the compute
# cores above. These are the cores that actually drive the fabric; landing them
# on top of a rank's compute cores is a classic quiet regression.
export CCL_WORKER_AFFINITY="${CCL_WORKER_AFFINITY:-42,43,44,45,46,47,94,95,96,97,98,99}"

# All 12 tiles visible to every rank, in a fixed order. Under FLAT this is the
# identity mapping, so it changes nothing today -- its job is to PIN the
# ordering so a future driver or module change cannot silently renumber the
# devices underneath patch 0001.
#
# Do NOT rewrite this per-rank to a single tile (the common Aurora idiom).
# Patch 0001 selects the device itself, by local rank, out of whatever is
# visible. Narrow the mask to one device and every rank sees only device 0,
# so local rank 1+ indexes past the end -- or, worse, all ranks land on the
# same tile and the run still "succeeds" with meaningless numbers.
export ZE_AFFINITY_MASK="${ZE_AFFINITY_MASK:-0,1,2,3,4,5,6,7,8,9,10,11}"
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
