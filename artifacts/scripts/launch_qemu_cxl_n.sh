#!/usr/bin/env bash
#
# Parameterized replacement for OCEAN's qemu_integration/launch_qemu_cxl.sh /
# launch_qemu_cxl1.sh, which only ever covered hosts 0 and 1 (and shared a
# single lsa1.raw file between them, which is a bug: each host needs its own
# LSA backing file). Launches guest <host_index> (0-9) against the CXL memory
# server, using a bridge/tap network already brought up by setup_network.sh.
#
# Usage:
#   launch_qemu_cxl_n.sh <host_index> [disk_image]
#
# disk_image defaults to the shared base image for host 0
# (OCEAN_BASE_IMG, raw) and to build/qemu<N>.qcow2 (an overlay created by
# provision_guest.sh) for every other host.
#
# Env overrides:
#   VM_MEMORY        guest RAM (default 16G; drop this for host counts >= 8)
#   CXL_MEM_SIZE      cxl-fmw.0.size (CXL fixed-memory-window / address space,
#                     default 4G). Does NOT control actual backing capacity --
#                     the memory-backend-file backing the CXL device is fixed
#                     at 1G, matching OCEAN's own qemu_integration/launch_qemu_cxl.sh
#                     and the guest's baked-in /usr/local/bin/setup_cxl_numa.sh,
#                     which hardcodes CXL_REGION_SIZE="1024M". Found the hard
#                     way: scaling the actual backing file up to match a
#                     larger CXL_MEM_SIZE (e.g. 4G) makes the guest's
#                     `ndctl create-namespace -m dax -r region0` hang
#                     indefinitely on this OCEAN build -- keeping the backing
#                     file at 1G (window can still be larger) avoids it. This
#                     also matches the ~1006MB usable-capacity ceiling
#                     documented in FINDINGS_AND_RUN_GUIDE.md.
#   CXL_MEMSIM_HOST/PORT  where the guest's CXL device model connects
#   CXL_TRANSPORT_MODE    tcp (default) | shm — QEMU-side CXL.mem/LSA backend
#   CXL_LATENCY_INJECT    1 (default) | 0 — enforce simulated CXL latency via
#                     spin-wait; 0 measures raw trap+IPC cost with no delay
#                     enforcement on top
#   FOREGROUND        1 to run in the foreground (default: background, with
#                     console log at $LOG_DIR/qemu-node<N>.log and a pidfile
#                     at $LOG_DIR/qemu-node<N>.pid)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

[[ $# -ge 1 ]] || die "usage: $(basename "$0") <host_index 0-9> [disk_image]"
N="$1"
[[ "${N}" =~ ^[0-9]$ ]] || die "host_index must be a single digit 0-9, got: ${N}"

if [[ $# -ge 2 ]]; then
    DISK_IMAGE="$2"
elif [[ "${N}" -eq 0 ]]; then
    DISK_IMAGE="${OCEAN_BASE_IMG}"
    DISK_FORMAT="raw"
else
    DISK_IMAGE="${OCEAN_BUILD_DIR}/qemu${N}.qcow2"
    DISK_FORMAT="qcow2"
fi
DISK_FORMAT="${DISK_FORMAT:-$( [[ "${DISK_IMAGE}" == *.qcow2 ]] && echo qcow2 || echo raw )}"
[[ -f "${DISK_IMAGE}" ]] || die "disk image not found: ${DISK_IMAGE} (run provision_guest.sh ${N} first?)"

QEMU_BINARY="${QEMU_BINARY:-/usr/local/bin/qemu-system-x86_64}"
command -v "${QEMU_BINARY}" >/dev/null || QEMU_BINARY="qemu-system-x86_64"

VM_MEMORY="${VM_MEMORY:-16G}"
CXL_MEM_SIZE="${CXL_MEM_SIZE:-4G}"
export CXL_MEMSIM_HOST="${CXL_MEMSIM_HOST:-127.0.0.1}"
export CXL_MEMSIM_PORT="${CXL_MEMSIM_PORT:-9999}"
export CXL_TRANSPORT_MODE="${CXL_TRANSPORT_MODE:-tcp}"
export CXL_HOST_ID="${N}"
export CXL_LATENCY_INJECT="${CXL_LATENCY_INJECT:-1}"

MAC="52:54:00:00:00:$(printf '%02x' $((N + 1)))"
TAP="tap${N}"
LSA_FILE="/dev/shm/lsa${N}.raw"
SHM_FILE="/dev/shm/cxlmemsim_shared"   # deliberately shared across all hosts — this is the pooled CXL memory

mkdir -p "${LOG_DIR}"
CONSOLE_LOG="${LOG_DIR}/qemu-node${N}.log"
PID_FILE="${LOG_DIR}/qemu-node${N}.pid"

# Idempotent: if node<N> is already up (by tap device, since the pidfile can
# point at an already-reaped `sudo` wrapper), don't launch a conflicting
# second instance against the same disk image/tap.
if pgrep -f "ifname=${TAP},script=no" >/dev/null 2>&1; then
    ok "node${N} already running (tap=${TAP}); not relaunching"
    exit 0
fi

# QEMU creates/sizes SHM_FILE itself on first attach (share=on); a stale file
# left over at the wrong size from a previous run with a different
# CXL_MEM_SIZE will make every subsequent guest fail to attach, so callers
# must keep CXL_MEM_SIZE consistent for the lifetime of one shared pool (or
# rm -f "${SHM_FILE}" /dev/shm/lsa*.raw before changing it).

QEMU_ARGS=(
    --enable-kvm -cpu "qemu64,+xsave,+rdtscp,+avx,+avx2,+sse4.1,+sse4.2,+avx512f,+avx512dq,+avx512ifma,+avx512cd,+avx512bw,+avx512vl,+avx512vbmi,+clflushopt"
    -m "${VM_MEMORY},maxmem=32G,slots=8"
    -smp 4
    -M q35,cxl=on
    -kernel "${OCEAN_BUILD_DIR}/bzImage"
    -append "root=/dev/sda rw console=ttyS0,115200 nokaslr"
    -drive "file=${DISK_IMAGE},index=0,media=disk,format=${DISK_FORMAT}"
    -netdev "tap,id=net0,ifname=${TAP},script=no,downscript=no"
    -device "virtio-net-pci,netdev=net0,mac=${MAC}"
    -fsdev "local,security_model=none,id=fsdev0,path=/dev/shm"
    -device "virtio-9p-pci,id=fs0,fsdev=fsdev0,mount_tag=hostshm,bus=pcie.0"
    -device "pxb-cxl,bus_nr=12,bus=pcie.0,id=cxl.1"
    -device "cxl-rp,port=0,bus=cxl.1,id=root_port13,chassis=0,slot=0"
    -device "cxl-rp,port=1,bus=cxl.1,id=root_port14,chassis=0,slot=1"
    -device "cxl-type3,bus=root_port13,persistent-memdev=cxl-mem1,lsa=cxl-lsa1,id=cxl-pmem0,sn=0x1"
    -device "cxl-type1,bus=root_port14,size=1G,cache-size=64M"
    -device "virtio-cxl-accel-pci,bus=pcie.0"
    -object "memory-backend-file,id=cxl-mem1,share=on,mem-path=${SHM_FILE},size=1G"
    -object "memory-backend-file,id=cxl-lsa1,share=on,mem-path=${LSA_FILE},size=1G"
    -M "cxl-fmw.0.targets.0=cxl.1,cxl-fmw.0.size=${CXL_MEM_SIZE}"
    -nographic
)

# Needs root regardless of /dev/kvm group membership: the tap devices were
# created by ocean_ensure_bridge() via sudo and are only attachable
# (script=no, no CAP_NET_ADMIN otherwise) by root. -E preserves the
# CXL_MEMSIM_HOST/PORT/TRANSPORT_MODE/HOST_ID env vars qemu needs.
RUN_AS=(sudo -E)

if [[ "${FOREGROUND:-0}" -eq 1 ]]; then
    exec "${RUN_AS[@]}" "${QEMU_BINARY}" "${QEMU_ARGS[@]}"
fi

log "launching node${N} (disk=${DISK_IMAGE}, tap=${TAP}, mac=${MAC}, mem=${VM_MEMORY}, cxl=${CXL_MEM_SIZE})"
nohup "${RUN_AS[@]}" "${QEMU_BINARY}" "${QEMU_ARGS[@]}" > "${CONSOLE_LOG}" 2>&1 &
echo $! > "${PID_FILE}"
ok "node${N} pid $(cat "${PID_FILE}"); console log: ${CONSOLE_LOG}"
