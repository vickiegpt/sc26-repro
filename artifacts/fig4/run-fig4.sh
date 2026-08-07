#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../scripts/common.sh"
source "${SCRIPT_DIR}/../scripts/ocean_hosts.sh"

HOST_COUNTS="2 4 6"
STREAM_ARRAY_SIZE=500000
OMP_NUM_THREADS_VAL=4
STREAM_GLIBC_TUNABLES="glibc.cpu.hwcaps=-AVX512F,-AVX512BW,-AVX512DQ,-AVX512VL,-AVX512CD,-AVX512VBMI,-AVX512IFMA,-AVX2,-AVX,-AVX_Fast_Unaligned_Load,-AVX_Fast_Unaligned_Store,-AVX_Fast_Copy_Backward,-AVX_Copy_Backward,-ERMS,-FSRM"
STREAM_TIMEOUT=3600
CXL_MEM_SIZE="1536M"
VM_MEMORY="16G"
CAPACITY_MB=2048
SKIP_LAUNCH=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --quick)        HOST_COUNTS="2"; STREAM_ARRAY_SIZE=100000; shift ;;
        --hosts)        HOST_COUNTS="$2"; shift 2 ;;
        --array-size)   STREAM_ARRAY_SIZE="$2"; shift 2 ;;
        --skip-launch)  SKIP_LAUNCH=1; shift ;;
        -h|--help)      echo "Usage: $0 [--quick] [--hosts '2 4 6'] [--array-size N] [--skip-launch]"; exit 0 ;;
        *)              die "unknown argument: $1" ;;
    esac
done

MAX_HOSTS="$(printf '%s\n' ${HOST_COUNTS} | sort -n | tail -1)"
[[ "${MAX_HOSTS}" -le 6 ]] || die "host counts must be <=6 (got ${MAX_HOSTS})"

RUN_ID="$(date +%Y%m%d-%H%M%S)"
RESULTS_DIR="${SCRIPT_DIR}/data"
RUN_LOG_DIR="${LOG_DIR}/fig4-${RUN_ID}"
mkdir -p "${RESULTS_DIR}" "${RUN_LOG_DIR}"
CSV="${RESULTS_DIR}/stream.csv"
WORK_CSV="${RUN_LOG_DIR}/stream.csv"
echo "hosts,kernel,rate_mb_s,avg_time,min_time,max_time" > "${WORK_CSV}"
sync_csv() { cp "${WORK_CSV}" "${CSV}"; }

if [[ "${SKIP_LAUNCH}" -eq 0 ]]; then
    log "bringing up ${MAX_HOSTS}-guest OCEAN deployment"
    ocean_ensure_bridge "${MAX_HOSTS}"
    ocean_start_server "${CAPACITY_MB}" "${OCEAN_QEMU_DIR}/topology_simple.txt"
    for ((n=0; n<MAX_HOSTS; n++)); do
        ocean_provision_guest "${n}"
        CXL_MEM_SIZE="${CXL_MEM_SIZE}" VM_MEMORY="${VM_MEMORY}" ocean_launch_guest "${n}"
    done
    for ((n=0; n<MAX_HOSTS; n++)); do ocean_wait_ssh "${n}"; done
else
    dim "--skip-launch: assuming guests are already up"
fi

log "building stream_mpi on node0 (cached after first run)"
STREAM_BIN="/root/stream_mpi_large_${STREAM_ARRAY_SIZE}"
if ! ocean_ssh 0 "test -x ${STREAM_BIN}" 2>/dev/null; then
    PATCH_PY="$(mktemp)"
    cat > "${PATCH_PY}" <<'PATCHEOF'
import sys
path = "/root/stream_mpi.c"
src = open(path).read()
inc_anchor = "# include <sys/time.h>\n"
src = src.replace(inc_anchor, inc_anchor + "# include <sys/mman.h>\n# include <fcntl.h>\n", 1)

helper = '''
static void *cxl_dax_base = NULL;
static size_t cxl_dax_offset = 0;
static void *alloc_stream_array(size_t bytes) {
    const char *dax_path = getenv("CXL_DAX_PATH");
    void *p;
    if (!dax_path) {
        if (posix_memalign(&p, 64, bytes) != 0) return NULL;
        return p;
    }
    size_t align = 2 * 1024 * 1024;
    size_t region = (bytes + align - 1) / align * align;
    if (cxl_dax_base == NULL) {
        int fd = open(dax_path, O_RDWR);
        cxl_dax_base = mmap(NULL, region * 3, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    }
    p = (char *)cxl_dax_base + cxl_dax_offset;
    cxl_dax_offset += region;
    return p;
}
'''
src = src.replace("int\nmain()", helper + "\nint\nmain()", 1)

for var in ("a", "b", "c"):
    old = f'    k = posix_memalign((void **)&{var}, array_alignment, array_bytes);\n    if (k != 0) {{\n        printf("Rank %d: Allocation of array {var} failed, return code is %d\\n",myrank,k);\n\t\tMPI_Abort(MPI_COMM_WORLD, 2);\n        exit(1);\n    }}'
    new = f'    {var} = alloc_stream_array(array_bytes);\n    if ({var} == NULL) {{\n        printf("Rank %d: Allocation of array {var} failed\\n",myrank);\n\t\tMPI_Abort(MPI_COMM_WORLD, 2);\n        exit(1);\n    }}'
    src = src.replace(old, new, 1)

open(path, "w").write(src)
PATCHEOF
    ocean_scp_to 0 "${PATCH_PY}" /root/patch_stream.py
    rm -f "${PATCH_PY}"
    ocean_ssh 0 "set -e; cd /root; rm -f stream_mpi.c; python3 -c \"import urllib.request; urllib.request.urlretrieve('https://www.cs.virginia.edu/stream/FTP/Code/Versions/stream_mpi.c', 'stream_mpi.c')\"; python3 patch_stream.py; PATH=/usr/local/bin:\$PATH mpicc -O3 -fopenmp -DSTREAM_ARRAY_SIZE=${STREAM_ARRAY_SIZE} -o ${STREAM_BIN} stream_mpi.c" || die "failed to build stream_mpi"
fi

for ((n = 1; n < MAX_HOSTS; n++)); do
    ocean_ssh "${n}" "test -x ${STREAM_BIN}" 2>/dev/null || \
        ocean_ssh 0 "scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -i /root/.ssh/id_rsa ${STREAM_BIN} root@$(ocean_node_ip "${n}"):${STREAM_BIN}"
done

run_stream() {
    local n_hosts="$1" hostfile="/root/hostfile.fig4.${n_hosts}"
    ocean_ssh 0 "
        : > ${hostfile}
        for ((i=0;i<${n_hosts};i++)); do echo \"node\$i slots=1\" >> ${hostfile}; done
        export CXL_DAX_PATH=/dev/dax0.0
        export OMP_NUM_THREADS=${OMP_NUM_THREADS_VAL}
        export GLIBC_TUNABLES='${STREAM_GLIBC_TUNABLES}'
        PATH=/usr/local/bin:\$PATH timeout ${STREAM_TIMEOUT} mpirun --allow-run-as-root --hostfile ${hostfile} --wdir /root -x CXL_DAX_PATH -x OMP_NUM_THREADS -x GLIBC_TUNABLES ${STREAM_BIN} 2>&1
    "
}

for hosts in ${HOST_COUNTS}; do
    log "STREAM @ ${hosts} host(s)"
    set +e; OUT="$(run_stream "${hosts}")"; RUN_EXIT=$?; set -e
    echo "${OUT}" > "${RUN_LOG_DIR}/stream_${hosts}hosts.log"
    [[ "${RUN_EXIT}" -ne 0 ]] && { warn "STREAM failed (exit ${RUN_EXIT}). Skipping."; continue; }
    
    ROWS="$(printf '%s\n' "${OUT}" | grep -E '^(Copy|Scale|Add|Triad):' || true)"
    [[ -z "${ROWS}" ]] && { warn "No STREAM output found."; continue; }

    while IFS= read -r line; do
        kernel="${line%%:*}"
        read -r _ rate avg min max <<< "${line}"
        echo "${hosts},${kernel},${rate},${avg},${min},${max}" >> "${WORK_CSV}"
        sync_csv
        dim "${kernel}: ${rate} MB/s"
    done <<< "${ROWS}"
done

python3 "${SCRIPT_DIR}/plot-fig4.py" "${CSV}" "${RESULTS_DIR}/stream.png"
exit $?

