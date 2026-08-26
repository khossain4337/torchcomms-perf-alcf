#!/bin/bash -x
#PBS -l select=2
#PBS -l place=scatter
#PBS -l walltime=00:30:00
#PBS -q workq
#PBS -A datascience
#PBS -l filesystems=home:tegu
#PBS -k doe
#PBS -e /lus/tegu/projects/datasets/software/testing/torchcomm_example/torchcomms-perf-alcf/jobs/errordir
#PBS -o /lus/tegu/projects/datasets/software/testing/torchcomm_example/torchcomms-perf-alcf/jobs/outdir
#PBS -j oe
#PBS -N tcperf_min

export TZ='/usr/share/zoneinfo/US/Central'

export BENCH_DIR=/lus/tegu/projects/datasets/software/testing/torchcomm_example/torchcomms-perf-alcf
export PERF_DIR=${BENCH_DIR}/perf_standalone
export OUT_DIR=${BENCH_DIR}/results/minimal_$(date +%Y-%m-%d-%H%M%S)

export COLLECTIVE=all_reduce
export MIN_SIZE=1024
export MAX_SIZE=67108864
export ITERS=100
export WARMUP=20
export SYNC_INTERVAL=1

NNODES=$(wc -l < $PBS_NODEFILE)
export NRANKS_PER_NODE=12
let NRANKS=${NNODES}*${NRANKS_PER_NODE}
export NRANKS

export MASTER_ADDR=$(head -n 1 $PBS_NODEFILE)-hsn0.hsn.cm.sunspot.alcf.anl.gov
export MASTER_PORT=2345

export WORLD_SIZE=${NRANKS}
export PALS_WORLD_SIZE=${NRANKS}
export TORCHCOMM_SIZE=${NRANKS}
export TORCHCOMM_LOCAL_SIZE=${NRANKS_PER_NODE}
export CCL_LOCAL_SIZE=${NRANKS_PER_NODE}

module add frameworks

unset CCL_OP_SYNC
export CCL_OP_SYNC=0
unset CCL_ATL_SYNC_COLL
export CCL_ATL_SYNC_COLL=0

export ZE_FLAT_DEVICE_HIERARCHY=FLAT
export FI_MR_CACHE_MONITOR=userfaultfd
export CCL_PROCESS_LAUNCHER=pmix
export CCL_ATL_TRANSPORT=mpi
export CCL_KVS_MODE=pmi

export TEST_BACKEND=xccl
export TEST_DEVICE=xpu
export TORCHCOMMS_BUILD_TAG=${FRAMEWORKS_VERSION:-unknown}
export PYTHONUNBUFFERED=1

export CPU_AFFINITY="list:4-7:8-11:12-15:16-19:20-23:24-27:56-59:60-63:64-67:68-71:72-75:76-79"
export CCL_WORKER_AFFINITY="42,43,44,45,46,47,94,95,96,97,98,99"
export ZE_AFFINITY_MASK="0,1,2,3,4,5,6,7,8,9,10,11"

mkdir -p ${OUT_DIR}


mpiexec -n ${NRANKS} -ppn ${NRANKS_PER_NODE} -l --line-buffer -envall \
    --cpu-bind ${CPU_AFFINITY} \
    -genv MASTER_ADDR ${MASTER_ADDR} \
    -genv MASTER_PORT ${MASTER_PORT} \
    -genv WORLD_SIZE ${NRANKS} \
    -genv PALS_WORLD_SIZE ${NRANKS} \
    -genv TORCHCOMM_SIZE ${NRANKS} \
    -genv TORCHCOMM_LOCAL_SIZE ${NRANKS_PER_NODE} \
    -genv CCL_LOCAL_SIZE ${NRANKS_PER_NODE} \
    bash -c "
        export RANK=\${PALS_RANKID:-\${PMIX_RANK}}
        export LOCAL_RANK=\${PALS_LOCAL_RANKID}
        export WORLD_SIZE=${NRANKS}

        export TORCHCOMM_RANK=\${RANK}
        export TORCHCOMM_SIZE=${NRANKS}
        export TORCHCOMM_LOCAL_RANK=\${LOCAL_RANK}
        export TORCHCOMM_LOCAL_SIZE=${NRANKS_PER_NODE}

        export CCL_LOCAL_RANK=\${LOCAL_RANK}
        export CCL_LOCAL_SIZE=${NRANKS_PER_NODE}

        export MASTER_ADDR=${MASTER_ADDR}
        export MASTER_PORT=${MASTER_PORT}

        unset TORCHCOMM_XCCL_BOOTSTRAP_UNIQUEID_EXCHANGE_METHOD
        export CCL_OP_SYNC=0
        export CCL_ATL_SYNC_COLL=0

        for v in RANK WORLD_SIZE LOCAL_RANK TORCHCOMM_RANK TORCHCOMM_SIZE TORCHCOMM_LOCAL_RANK; do
            if [ -z \"\${!v}\" ]; then
                echo FATAL rank=\${PALS_RANKID:-?} on \$(hostname): \$v is empty >&2
                env | grep -E '^(PMI|PALS|TORCHCOMM)' | sort >&2
                exit 1
            fi
        done

        if [ \$RANK = 0 ]; then
            echo [rank0] RANK=\$RANK WORLD_SIZE=\$WORLD_SIZE LOCAL_RANK=\$LOCAL_RANK >&2
            echo [rank0] TORCHCOMM_RANK=\$TORCHCOMM_RANK TORCHCOMM_SIZE=\$TORCHCOMM_SIZE >&2
            echo [rank0] TORCHCOMM_LOCAL_RANK=\$TORCHCOMM_LOCAL_RANK TORCHCOMM_LOCAL_SIZE=\$TORCHCOMM_LOCAL_SIZE >&2
            echo [rank0] CCL_LOCAL_RANK=\$CCL_LOCAL_RANK CCL_LOCAL_SIZE=\$CCL_LOCAL_SIZE >&2
            echo [rank0] MASTER=\$MASTER_ADDR:\$MASTER_PORT >&2
        fi

        exec python ${PERF_DIR}/collective_perf_test.py ${COLLECTIVE} \
            --min-size ${MIN_SIZE} --max-size ${MAX_SIZE} \
            --iters ${ITERS} --warmup ${WARMUP} \
            --sync-interval ${SYNC_INTERVAL} \
            --csv --output-dir ${OUT_DIR}/torchcomms
    "

mpiexec -n ${NRANKS} -ppn ${NRANKS_PER_NODE} -l --line-buffer -envall \
    --cpu-bind ${CPU_AFFINITY} \
    -genv MASTER_ADDR ${MASTER_ADDR} \
    -genv MASTER_PORT ${MASTER_PORT} \
    -genv WORLD_SIZE ${NRANKS} \
    -genv PALS_WORLD_SIZE ${NRANKS} \
    -genv TORCHCOMM_SIZE ${NRANKS} \
    -genv TORCHCOMM_LOCAL_SIZE ${NRANKS_PER_NODE} \
    -genv CCL_LOCAL_SIZE ${NRANKS_PER_NODE} \
    bash -c "
        export RANK=\${PALS_RANKID:-\${PMIX_RANK}}
        export LOCAL_RANK=\${PALS_LOCAL_RANKID}
        export WORLD_SIZE=${NRANKS}

        export TORCHCOMM_RANK=\${RANK}
        export TORCHCOMM_SIZE=${NRANKS}
        export TORCHCOMM_LOCAL_RANK=\${LOCAL_RANK}
        export TORCHCOMM_LOCAL_SIZE=${NRANKS_PER_NODE}

        export CCL_LOCAL_RANK=\${LOCAL_RANK}
        export CCL_LOCAL_SIZE=${NRANKS_PER_NODE}

        export MASTER_ADDR=${MASTER_ADDR}
        export MASTER_PORT=${MASTER_PORT}

        unset TORCHCOMM_XCCL_BOOTSTRAP_UNIQUEID_EXCHANGE_METHOD
        export CCL_OP_SYNC=0
        export CCL_ATL_SYNC_COLL=0

        for v in RANK WORLD_SIZE LOCAL_RANK TORCHCOMM_RANK TORCHCOMM_SIZE TORCHCOMM_LOCAL_RANK; do
            if [ -z \"\${!v}\" ]; then
                echo FATAL rank=\${PALS_RANKID:-?} on \$(hostname): \$v is empty >&2
                env | grep -E '^(PMI|PALS|TORCHCOMM)' | sort >&2
                exit 1
            fi
        done

        if [ \$RANK = 0 ]; then
            echo [rank0] RANK=\$RANK WORLD_SIZE=\$WORLD_SIZE LOCAL_RANK=\$LOCAL_RANK >&2
            echo [rank0] TORCHCOMM_RANK=\$TORCHCOMM_RANK TORCHCOMM_SIZE=\$TORCHCOMM_SIZE >&2
            echo [rank0] TORCHCOMM_LOCAL_RANK=\$TORCHCOMM_LOCAL_RANK TORCHCOMM_LOCAL_SIZE=\$TORCHCOMM_LOCAL_SIZE >&2
            echo [rank0] CCL_LOCAL_RANK=\$CCL_LOCAL_RANK CCL_LOCAL_SIZE=\$CCL_LOCAL_SIZE >&2
            echo [rank0] MASTER=\$MASTER_ADDR:\$MASTER_PORT >&2
        fi

        exec python ${PERF_DIR}/collective_perf_test.py ${COLLECTIVE} --c10d \
            --min-size ${MIN_SIZE} --max-size ${MAX_SIZE} \
            --iters ${ITERS} --warmup ${WARMUP} \
            --sync-interval ${SYNC_INTERVAL} \
            --csv --output-dir ${OUT_DIR}/c10d
    "

mpiexec -n ${NRANKS} -ppn ${NRANKS_PER_NODE} -l --line-buffer -envall \
    --cpu-bind ${CPU_AFFINITY} \
    -genv MASTER_ADDR ${MASTER_ADDR} \
    -genv MASTER_PORT ${MASTER_PORT} \
    -genv WORLD_SIZE ${NRANKS} \
    -genv PALS_WORLD_SIZE ${NRANKS} \
    -genv TORCHCOMM_SIZE ${NRANKS} \
    -genv TORCHCOMM_LOCAL_SIZE ${NRANKS_PER_NODE} \
    -genv CCL_LOCAL_SIZE ${NRANKS_PER_NODE} \
    bash -c "
        export RANK=\${PALS_RANKID:-\${PMIX_RANK}}
        export LOCAL_RANK=\${PALS_LOCAL_RANKID}
        export WORLD_SIZE=${NRANKS}

        export TORCHCOMM_RANK=\${RANK}
        export TORCHCOMM_SIZE=${NRANKS}
        export TORCHCOMM_LOCAL_RANK=\${LOCAL_RANK}
        export TORCHCOMM_LOCAL_SIZE=${NRANKS_PER_NODE}

        export CCL_LOCAL_RANK=\${LOCAL_RANK}
        export CCL_LOCAL_SIZE=${NRANKS_PER_NODE}

        export MASTER_ADDR=${MASTER_ADDR}
        export MASTER_PORT=${MASTER_PORT}

        unset TORCHCOMM_XCCL_BOOTSTRAP_UNIQUEID_EXCHANGE_METHOD
        export CCL_OP_SYNC=0
        export CCL_ATL_SYNC_COLL=0

        for v in RANK WORLD_SIZE LOCAL_RANK TORCHCOMM_RANK TORCHCOMM_SIZE TORCHCOMM_LOCAL_RANK; do
            if [ -z \"\${!v}\" ]; then
                echo FATAL rank=\${PALS_RANKID:-?} on \$(hostname): \$v is empty >&2
                env | grep -E '^(PMI|PALS|TORCHCOMM)' | sort >&2
                exit 1
            fi
        done

        if [ \$RANK = 0 ]; then
            echo [rank0] RANK=\$RANK WORLD_SIZE=\$WORLD_SIZE LOCAL_RANK=\$LOCAL_RANK >&2
            echo [rank0] TORCHCOMM_RANK=\$TORCHCOMM_RANK TORCHCOMM_SIZE=\$TORCHCOMM_SIZE >&2
            echo [rank0] TORCHCOMM_LOCAL_RANK=\$TORCHCOMM_LOCAL_RANK TORCHCOMM_LOCAL_SIZE=\$TORCHCOMM_LOCAL_SIZE >&2
            echo [rank0] CCL_LOCAL_RANK=\$CCL_LOCAL_RANK CCL_LOCAL_SIZE=\$CCL_LOCAL_SIZE >&2
            echo [rank0] MASTER=\$MASTER_ADDR:\$MASTER_PORT >&2
        fi

        exec python ${PERF_DIR}/collective_perf_test.py ${COLLECTIVE} --c10d-torchcomms \
            --min-size ${MIN_SIZE} --max-size ${MAX_SIZE} \
            --iters ${ITERS} --warmup ${WARMUP} \
            --sync-interval ${SYNC_INTERVAL} \
            --csv --output-dir ${OUT_DIR}/c10d_torchcomms
    "

echo "results: ${OUT_DIR}"
