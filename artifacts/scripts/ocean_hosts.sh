# OCEAN multi-guest orchestration helpers, shared by run-fig{3,4,5}.sh.
# Source it (after common.sh), don't execute it.
#
#   source "${ARTIFACTS_DIR}/scripts/common.sh"
#   source "${ARTIFACTS_DIR}/scripts/ocean_hosts.sh"
#
# Node numbering: node0 == the original build/qemu.img (192.168.100.10,
# already provisioned). node1-9 are qcow2 overlays provisioned on demand
# (192.168.100.11-19). All nodes share one root SSH key (every clone is
# byte-identical, and the base image already trusts its own key).

ocean_node_ip()   { printf '%s.%d' "${OCEAN_BRIDGE_SUBNET_PREFIX}" "$((10 + $1))"; }
ocean_node_name() { printf 'node%d' "$1"; }

ocean_ssh() {
    local n="$1"; shift
    ssh -i "${OCEAN_GUEST_SSH_KEY}" "${OCEAN_SSH_OPTS[@]}" "root@$(ocean_node_ip "${n}")" "$@"
}

ocean_scp_to() {
    local n="$1" src="$2" dst="$3"
    scp -i "${OCEAN_GUEST_SSH_KEY}" "${OCEAN_SSH_OPTS[@]}" -q "${src}" "root@$(ocean_node_ip "${n}"):${dst}"
}

ocean_wait_ssh() {
    local n="$1" timeout="${2:-180}" waited=0
    dim "waiting for node${n} ($(ocean_node_ip "${n}")) ssh..."
    while ! ocean_ssh "${n}" true 2>/dev/null; do
        sleep 3; waited=$((waited + 3))
        [[ "${waited}" -lt "${timeout}" ]] || die "node${n} did not come up over ssh within ${timeout}s (see ${LOG_DIR}/qemu-node${n}.log)"
    done
    ok "node${n} ssh ready (${waited}s)"
}

# ---------------------------------------------------------------- network ---

# Idempotent version of OCEAN's script/setup_network.sh: brings br0 up if
# missing, and ensures tap0..tap(num_vms-1) exist and are attached.
ocean_ensure_bridge() {
    local num_vms="$1" i
    if ! ip link show br0 >/dev/null 2>&1; then
        log "creating br0 (192.168.100.1/24)"
        sudo ip link add br0 type bridge
        sudo ip link set br0 up
        sudo ip addr add "${OCEAN_BRIDGE_SUBNET_PREFIX}.1/24" dev br0
    fi
    for ((i = 0; i < num_vms; i++)); do
        if ! ip link show "tap${i}" >/dev/null 2>&1; then
            sudo ip tuntap add "tap${i}" mode tap
            sudo ip link set "tap${i}" up
            sudo ip link set "tap${i}" master br0
            ok "tap${i} attached to br0"
        fi
    done
}

# ------------------------------------------------------------- image prep ---

ocean_ensure_base_qcow() {
    [[ -f "${OCEAN_BASE_IMG}" ]] || die "base image missing: ${OCEAN_BASE_IMG}"
    if [[ -f "${OCEAN_BASE_QCOW}" && "${OCEAN_BASE_QCOW}" -nt "${OCEAN_BASE_IMG}" ]]; then
        dim "base qcow2 already up to date: ${OCEAN_BASE_QCOW}"
        return
    fi
    log "converting ${OCEAN_BASE_IMG} (raw) -> qcow2 base (one-time, ~26GB, several minutes)"
    # -U/--force-share: node0 normally has this file open (raw images take an
    # exclusive write lock), so a plain read-only open here would fail with
    # "Failed to get shared write lock". This snapshots whatever is on disk
    # at the moment of conversion, which is fine for provisioning purposes.
    qemu-img convert -U -f raw -O qcow2 "${OCEAN_BASE_IMG}" "${OCEAN_BASE_QCOW}.tmp"
    mv "${OCEAN_BASE_QCOW}.tmp" "${OCEAN_BASE_QCOW}"
    ok "base qcow2 ready: ${OCEAN_BASE_QCOW}"
}

# Create (if missing) and customize a qcow2 overlay for node <n>: hostname,
# the static-IP line in setup_cxl_numa.sh, and (for n>=8, beyond the base
# image's baked-in node0-node7 /etc/hosts entries) an /etc/hosts addition.
# node0 needs none of this -- it *is* the base image.
ocean_provision_guest() {
    local n="$1"
    [[ "${n}" -eq 0 ]] && { dim "node0 is the base image, nothing to provision"; return; }

    local overlay="${OCEAN_BUILD_DIR}/qemu${n}.qcow2"
    if [[ -f "${overlay}" ]]; then
        dim "node${n} overlay already provisioned: ${overlay}"
        return
    fi

    ocean_ensure_base_qcow

    log "provisioning node${n} ($(ocean_node_ip "${n}"))"
    qemu-img create -f qcow2 -b "${OCEAN_BASE_QCOW}" -F qcow2 "${overlay}.tmp" >/dev/null

    local ip; ip="$(ocean_node_ip "${n}")"
    local hosts_extra=""
    if [[ "${n}" -ge 8 ]]; then
        # base image's /etc/hosts only has node0-node7 baked in.
        hosts_extra="grep -q node${n} /etc/hosts || echo '${ip} node${n}' >> /etc/hosts"
    fi

    sudo virt-customize -q -a "${overlay}.tmp" \
        --hostname "node${n}" \
        --run-command "sed -i 's/192\.168\.100\.10\/24/${ip}\/24/' /usr/local/bin/setup_cxl_numa.sh" \
        ${hosts_extra:+--run-command "${hosts_extra}"} \
        || die "virt-customize failed for node${n}"

    mv "${overlay}.tmp" "${overlay}"
    ok "node${n} overlay ready: ${overlay}"
}

# ----------------------------------------------------------------- server ---

# Start the CXL memory server. Extra args (e.g. --comm-mode distributed
# --transport-mode tcp --tcp-peers ...) are forwarded as-is.
ocean_start_server() {
    local capacity="${1:-4096}" topology="${2:-${OCEAN_QEMU_DIR}/topology_simple.txt}"; shift 2 || shift $#
    mkdir -p "${LOG_DIR}"
    local log_file="${LOG_DIR}/cxlmemsim_server.log"
    local pid_file="${LOG_DIR}/cxlmemsim_server.pid"

    if [[ -f "${pid_file}" ]] && kill -0 "$(cat "${pid_file}")" 2>/dev/null; then
        dim "cxlmemsim_server already running (pid $(cat "${pid_file}"))"
        return
    fi
    # The pidfile check above misses servers orphaned by a killed parent
    # script (still holding port 9999 with no live pidfile pointing at them).
    if pgrep -f "^\./cxlmemsim_server --port" >/dev/null 2>&1; then
        warn "found an orphaned cxlmemsim_server not tracked by the pidfile; killing it first"
        pkill -9 -f "^\./cxlmemsim_server --port" 2>/dev/null || true
        sleep 1
    fi

    log "starting cxlmemsim_server (capacity=${capacity}MB, topology=${topology})"
    ( cd "${OCEAN_BUILD_DIR}" && \
      nohup ./cxlmemsim_server --port 9999 --topology "${topology}" --capacity "${capacity}" "$@" \
      > "${log_file}" 2>&1 & echo $! > "${pid_file}" )
    sleep 2
    kill -0 "$(cat "${pid_file}")" 2>/dev/null || die "cxlmemsim_server exited immediately; see ${log_file}"
    ok "cxlmemsim_server pid $(cat "${pid_file}"); log: ${log_file}"
}

ocean_stop_server() {
    local pid_file="${LOG_DIR}/cxlmemsim_server.pid"
    if [[ -f "${pid_file}" ]]; then
        kill "$(cat "${pid_file}")" 2>/dev/null || true
        rm -f "${pid_file}"
    fi
    pkill -9 -f "./cxlmemsim_server --port" 2>/dev/null || true
}

# ------------------------------------------------------------------ guest ---

ocean_launch_guest() {
    local n="$1"; shift
    # Deliberately not $SCRIPT_DIR: every run-figN.sh also defines a
    # SCRIPT_DIR (its own directory) before sourcing this file, and since
    # sourced scripts share the caller's variable namespace, that shadows
    # any $SCRIPT_DIR set here. ARTIFACTS_DIR (from common.sh) is unique.
    "${ARTIFACTS_DIR}/scripts/launch_qemu_cxl_n.sh" "${n}" "$@"
}

ocean_stop_guest() {
    local n="$1"
    local pid_file="${LOG_DIR}/qemu-node${n}.pid"
    # The pidfile holds the `sudo -E` wrapper's pid, which sudo may have
    # already reaped after exec'ing qemu — kill both the recorded pid and
    # the actual qemu-system-x86_64 process by its tap device, which is
    # unique per node.
    if [[ -f "${pid_file}" ]]; then
        sudo kill -9 "$(cat "${pid_file}")" 2>/dev/null || true
        rm -f "${pid_file}"
    fi
    sudo pkill -9 -f "ifname=tap${n},script=no" 2>/dev/null || true
}

ocean_stop_all() {
    local n
    for n in 0 1 2 3 4 5 6 7 8 9; do ocean_stop_guest "${n}"; done
    ocean_stop_server
}
