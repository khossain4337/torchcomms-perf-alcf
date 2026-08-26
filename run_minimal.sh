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

BENCH_DIR=/lus/tegu/projects/datasets/software/testing/torchcomm_example/torchcomms-perf-alcf
PERF_DIR=${BENCH_DIR}/perf_standalone
OUT_DIR=${BENCH_DIR}/results/minimal_$(date +%Y-%m-%d-%H%M%S)

COLLECTIVE=all_reduce
MIN_SIZE=1024
MAX_SIZE=67108864
ITERS=100
WARMUP=20
SYNC_INTERVAL=1

NNODES=$(wc -l < $PBS_NODEFILE)
NRANKS_PER_NODE=12
let NRANKS=${NNODES}*${NRANKS_PER_NODE}

MASTER_ADDR=$(head -n 1 $PBS_NODEFILE)-hsn0.hsn.cm.sunspot.alcf.anl.gov
MASTER_PORT=2345

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

RANK_ENV=${BENCH_DIR}/rank_env_minimal.sh

cat > ${RANK_ENV} <<'EOF'
#!/bin/bash
export RANK=${PMI_RANK:-${PMIX_RANK:-${PALS_RANKID}}}
export WORLD_SIZE=${PMI_SIZE:-${PALS_NRANKS}}
export LOCAL_RANK=${PALS_LOCAL_RANKID}
export CCL_LOCAL_RANK=${PALS_LOCAL_RANKID}
export CCL_LOCAL_SIZE=${PALS_LOCAL_SIZE}
unset TORCHCOMM_XCCL_BOOTSTRAP_UNIQUEID_EXCHANGE_METHOD
exec "$@"
EOF
chmod +x ${RANK_ENV}

mpiexec -n ${NRANKS} -ppn ${NRANKS_PER_NODE} -l --line-buffer --cpu-bind ${CPU_AFFINITY} \
    -env MASTER_ADDR=${MASTER_ADDR} \
    -env MASTER_PORT=${MASTER_PORT} \
    ${RANK_ENV} \
    python ${PERF_DIR}/collective_perf_test.py ${COLLECTIVE} \
    --min-size ${MIN_SIZE} --max-size ${MAX_SIZE} \
    --iters ${ITERS} --warmup ${WARMUP} \
    --sync-interval ${SYNC_INTERVAL} \
    --csv --output-dir ${OUT_DIR}/torchcomms

mpiexec -n ${NRANKS} -ppn ${NRANKS_PER_NODE} -l --line-buffer --cpu-bind ${CPU_AFFINITY} \
    -env MASTER_ADDR=${MASTER_ADDR} \
    -env MASTER_PORT=${MASTER_PORT} \
    ${RANK_ENV} \
    python ${PERF_DIR}/collective_perf_test.py ${COLLECTIVE} --c10d \
    --min-size ${MIN_SIZE} --max-size ${MAX_SIZE} \
    --iters ${ITERS} --warmup ${WARMUP} \
    --sync-interval ${SYNC_INTERVAL} \
    --csv --output-dir ${OUT_DIR}/c10d

mpiexec -n ${NRANKS} -ppn ${NRANKS_PER_NODE} -l --line-buffer --cpu-bind ${CPU_AFFINITY} \
    -env MASTER_ADDR=${MASTER_ADDR} \
    -env MASTER_PORT=${MASTER_PORT} \
    ${RANK_ENV} \
    python ${PERF_DIR}/collective_perf_test.py ${COLLECTIVE} --c10d-torchcomms \
    --min-size ${MIN_SIZE} --max-size ${MAX_SIZE} \
    --iters ${ITERS} --warmup ${WARMUP} \
    --sync-interval ${SYNC_INTERVAL} \
    --csv --output-dir ${OUT_DIR}/c10d_torchcomms

echo "results: ${OUT_DIR}"
