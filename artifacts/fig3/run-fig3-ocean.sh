#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../scripts/common.sh"
source "${SCRIPT_DIR}/../scripts/ocean_hosts.sh"

MAX_SIZE_MB=1024
STRIDE=64
REPS=4
NUM_GUESTS=2
RUN_TIMEOUT=600
BENCH_HOST=0
CXL_MEM_SIZE="4G"
VM_MEMORY="16G"
CAPACITY_MB=4096
SKIP_LAUNCH=0

HOST_LMBENCH_BIN="${HOST_LMBENCH_BIN:-./lat_mem_rd}"
LMBENCH_BIN="/root/lat_mem_rd"
PARSE_SCRIPT="${SCRIPT_DIR}/../scripts/parse_lat_mem_rd.py"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --max-size)     MAX_SIZE_MB="$2"; shift 2 ;;
        --stride)       STRIDE="$2"; shift 2 ;;
        --reps)         REPS="$2"; shift 2 ;;
        --bench-host)   BENCH_HOST="$2"; shift 2 ;;
        --skip-launch)  SKIP_LAUNCH=1; shift ;;
        *)              die "unknown argument: $1" ;;
    esac
done

RUN_ID="$(date +%Y%m%d-%H%M%S)"
RESULTS_DIR="${SCRIPT_DIR}/data"
RUN_LOG_DIR="${LOG_DIR}/fig3-${RUN_ID}"
mkdir -p "${RESULTS_DIR}" "${RUN_LOG_DIR}"

RAW_OUT="${RUN_LOG_DIR}/ocean_board.log"
CSV="${RESULTS_DIR}/ocean.csv"

# ------------------------------------------------------------- deployment ---
if [[ "${SKIP_LAUNCH}" -eq 0 ]]; then
    log "bringing up ${NUM_GUESTS}-guest OCEAN deployment"
    ocean_ensure_bridge "${NUM_GUESTS}"
    ocean_start_server "${CAPACITY_MB}" "${OCEAN_QEMU_DIR}/topology_simple.txt"
    for ((local_n=0; local_n<NUM_GUESTS; local_n++)); do
        ocean_provision_guest "${local_n}"
        CXL_MEM_SIZE="${CXL_MEM_SIZE}" VM_MEMORY="${VM_MEMORY}" ocean_launch_guest "${local_n}"
    done
    for ((local_n=0; local_n<NUM_GUESTS; local_n++)); do
        ocean_wait_ssh "${local_n}"
    done
else
    dim "--skip-launch: assuming guests are already up"
fi

# -------------------------------------------------------- setup & execute ---
[[ -f "${HOST_LMBENCH_BIN}" ]] || die "lat_mem_rd not found on host at: ${HOST_LMBENCH_BIN}"
ocean_scp_to "${BENCH_HOST}" "${HOST_LMBENCH_BIN}" "${LMBENCH_BIN}"
ocean_ssh "${BENCH_HOST}" "chmod +x ${LMBENCH_BIN}"

ocean_ssh "${BENCH_HOST}" "daxctl reconfigure-device dax0.0 --mode=system-ram" >/dev/null || true
CXL_NODE="$(ocean_ssh "${BENCH_HOST}" "daxctl list | awk -F: '/target_node/ {print \$2}' | tr -d ' ,\"' | head -n1")"
[[ -n "${CXL_NODE}" ]] || die "no CXL NUMA node found on node${BENCH_HOST}"

log "Running lat_mem_rd on OCEAN for up to ${MAX_SIZE_MB} MB..."
# We wrap the output in the same markers SimCXL uses so your parser reads it identically
ocean_ssh "${BENCH_HOST}" \
    "echo '=====CXL lat_mem_rd -t -N ${REPS} ${MAX_SIZE_MB} ${STRIDE} start=====' && \
     timeout ${RUN_TIMEOUT} numactl --cpunodebind=0 --membind=${CXL_NODE} ${LMBENCH_BIN} -t -N ${REPS} ${MAX_SIZE_MB} ${STRIDE} && \
     echo '=====CXL lat_mem_rd -t -N ${REPS} ${MAX_SIZE_MB} ${STRIDE} finish====='" > "${RAW_OUT}" 2>&1

log "Parsing OCEAN results using parse_lat_mem_rd.py..."
if [[ -f "${PARSE_SCRIPT}" ]]; then
    python3 "${PARSE_SCRIPT}" "${RAW_OUT}" "${CSV}"
    ok "OCEAN data parsing complete! CSV saved to ${CSV}"
else
    die "Parser script not found at ${PARSE_SCRIPT}!"
fi
