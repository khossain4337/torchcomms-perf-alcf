#!/bin/bash
# sites/aurora.sh — ALCF Aurora (PVC, PBS + PALS/PMIx).
#
# Same architecture as Sunspot, but the naming does NOT carry over -- do not
# copy Sunspot's forms here.
#
# AURORA DOES NOT TAKE THE -hsn0 FORM. Use the bare `.hsn.cm.aurora.alcf.anl.gov`
# suffix. Both forms answer in DNS from a UAN (2026-08-26):
#
#   x4305c0s1b0n0-hsn0.hsn.cm.aurora.alcf.anl.gov -> 1 address  (10.112.163.147)
#   x4305c0s1b0n0.hsn.cm.aurora.alcf.anl.gov      -> 8 addresses, one per NIC
#
# so resolution is NOT the discriminator, and an earlier version of this file
# picked -hsn0 by reasoning from the single-A answer. That reasoning is exactly
# what broke Sunspot: the -hsn0 name there resolved perfectly and still hung.
# The bare form is what works on Aurora, per the user (2026-08-26).
TCPERF_HSN_SUFFIX=".hsn.cm.aurora.alcf.anl.gov"

# Rendezvous over HSN; .hostmgmt also works (both PASS at 2 nodes, 2026-10-29).
# HSN chosen for full scale. `:=` keeps a per-run override:
#     TCPERF_RDZV_SUFFIX=".hostmgmt.cm.aurora.alcf.anl.gov" bin/tc-perf-smoke
: "${TCPERF_RDZV_SUFFIX:=$TCPERF_HSN_SUFFIX}"

TCPERF_TILES_PER_NODE=12
TCPERF_DEFAULT_RPN=12

# Default resolves to frameworks/2026.1.0 (2026-10-29). Pin via
# TCPERF_MODULE_LOAD for reproducibility across a maintenance.
TCPERF_MODULE_LOAD='module add frameworks'

export TEST_BACKEND="${TEST_BACKEND:-xccl}"
export TEST_DEVICE="${TEST_DEVICE:-xpu}"

export ZE_FLAT_DEVICE_HIERARCHY="${ZE_FLAT_DEVICE_HIERARCHY:-FLAT}"

# Node layout = Sunspot (lscpu + xpu-smi, 2026-10-29); reasoning in sites/sunspot.sh.
export CPU_AFFINITY="${CPU_AFFINITY:-list:4-7:8-11:12-15:16-19:20-23:24-27:56-59:60-63:64-67:68-71:72-75:76-79}"
export CCL_WORKER_AFFINITY="${CCL_WORKER_AFFINITY:-42,43,44,45,46,47,94,95,96,97,98,99}"
# Keep all 12 visible: patch 0001 picks the tile by local rank.
export ZE_AFFINITY_MASK="${ZE_AFFINITY_MASK:-0,1,2,3,4,5,6,7,8,9,10,11}"
export CCL_ATL_TRANSPORT="${CCL_ATL_TRANSPORT:-mpi}"
export CCL_KVS_MODE="${CCL_KVS_MODE:-pmi}"
export CCL_PROCESS_LAUNCHER="${CCL_PROCESS_LAUNCHER:-pmix}"

# See the CCL_ATL_SYNC_COLL / CCL_OP_SYNC note in sites/sunspot.sh — re-check
# `env | grep CCL_` on Aurora before trusting any async-vs-sync comparison.
