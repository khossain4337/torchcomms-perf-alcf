#!/bin/bash
# sites/generic.sh — fallback when hostname detection finds nothing known.
#
# Deliberately minimal. It exists so `tc-perf-doctor` can run on an unknown
# login node and tell you what to fill in, not so you can benchmark blind.
#
# To add your machine: copy this to sites/<yourname>.sh, fill in the values,
# and either extend tcperf_detect_site() in sites/common.sh or export
# TCPERF_SITE=<yourname>.

TCPERF_HSN_SUFFIX=""            # bare nodenames assumed routable
TCPERF_TILES_PER_NODE=1
TCPERF_DEFAULT_RPN=1
TCPERF_MODULE_LOAD=""           # nothing to load; bring your own env

export TEST_BACKEND="${TEST_BACKEND:-xccl}"
export TEST_DEVICE="${TEST_DEVICE:-xpu}"
