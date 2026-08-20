#!/bin/bash
# sites/aurora.sh — ALCF Aurora (PVC, PBS + PALS/PMIx).
#
# Same architecture as Sunspot; the differences are the DNS suffix and the
# module names. VERIFIED on aurora-uan-0011 (Aug 2026):
#
#   x4305c0s1b0n0-hsn0.hsn.cm.aurora.alcf.anl.gov -> 10.112.163.147   (single A)
#   x4305c0s1b0n0.hsn.cm.aurora.alcf.anl.gov      -> 8 addresses      (multi-homed)
#
# Use the -hsn0 form: rendezvous needs one stable address that every rank
# resolves identically.
TCPERF_HSN_SUFFIX="-hsn0.hsn.cm.aurora.alcf.anl.gov"

TCPERF_TILES_PER_NODE=12
TCPERF_DEFAULT_RPN=12

# `module avail frameworks` on Aurora (Aug 2026) offers 2025.3.1 and 2025.2.0;
# bare `frameworks` resolves to the default. Pin a version from the job script
# via TCPERF_MODULE_LOAD when you need reproducibility across a maintenance.
TCPERF_MODULE_LOAD='module add frameworks'

export TEST_BACKEND="${TEST_BACKEND:-xccl}"
export TEST_DEVICE="${TEST_DEVICE:-xpu}"

export ZE_FLAT_DEVICE_HIERARCHY="${ZE_FLAT_DEVICE_HIERARCHY:-FLAT}"
export CCL_ATL_TRANSPORT="${CCL_ATL_TRANSPORT:-mpi}"
export CCL_KVS_MODE="${CCL_KVS_MODE:-pmi}"
export CCL_PROCESS_LAUNCHER="${CCL_PROCESS_LAUNCHER:-pmix}"

# See the CCL_ATL_SYNC_COLL / CCL_OP_SYNC note in sites/sunspot.sh — re-check
# `env | grep CCL_` on Aurora before trusting any async-vs-sync comparison.
