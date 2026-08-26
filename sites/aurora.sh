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

# Rendezvous suffix: LEFT UNSET DELIBERATELY, so it falls back to
# TCPERF_HSN_SUFFIX above.
#
# Sunspot needs .hostmgmt for MASTER_ADDR (see the long note in sites/sunspot.sh
# -- the fabric address hangs the XCCL UniqueID exchange there). Whether Aurora
# needs the same is UNKNOWN: nothing has ever been benchmarked on Aurora through
# this repo, and the -hsn0 lesson above is precisely that Aurora's naming does
# not follow Sunspot's. Guessing .hostmgmt here would repeat the mistake in the
# other direction.
#
# x4305c0s0b0n0.hostmgmt.cm.aurora.alcf.anl.gov does resolve (10.115.34.38), so
# if the first real Aurora job hangs at bootstrap, this is the one line to try:
#
#     TCPERF_RDZV_SUFFIX=".hostmgmt.cm.aurora.alcf.anl.gov"
#
# tc-perf-doctor resolves whatever is in effect before anything is launched.

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
