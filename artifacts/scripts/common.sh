# Shared paths, constants, and logging helpers for setup-tools.sh and the
# reproduce-*.sh scripts. Source it, don't execute it:
#   source "${ARTIFACTS_DIR}/scripts/common.sh"

_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARTIFACTS_DIR="$(cd "${_COMMON_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${ARTIFACTS_DIR}/.." && pwd)"
unset _COMMON_DIR

SIMCXL_DIR="${ARTIFACTS_DIR}/tools/SimCXL"
OCEAN_DIR="${ARTIFACTS_DIR}/tools/OCEAN"
RESOURCES_DIR="${ARTIFACTS_DIR}/resources"
LOG_DIR="${ARTIFACTS_DIR}/logs"

GEM5_BIN_REL="build/X86/gem5.opt"

# ------------------------------------------------------------- OCEAN hosts ---
# Shared by scripts/ocean_hosts.sh and the fig3/fig4/fig5 runners.

OCEAN_BUILD_DIR="${OCEAN_DIR}/build"
OCEAN_QEMU_DIR="${OCEAN_DIR}/qemu_integration"
OCEAN_BASE_IMG="${OCEAN_BUILD_DIR}/qemu.img"          # raw, host0/node0 image
OCEAN_BASE_QCOW="${OCEAN_BUILD_DIR}/qemu-base.qcow2"  # converted once, backing file for overlays
OCEAN_GUEST_SSH_KEY="${OCEAN_BUILD_DIR}/guest_id_rsa" # root key shared by every clone of the base image
OCEAN_BRIDGE_SUBNET_PREFIX="192.168.100"
OCEAN_SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
                -o ConnectTimeout=10 -o LogLevel=ERROR)

# The Linux kernel + disk image SimCXL's README links to.
DRIVE_URL="https://drive.google.com/drive/folders/1cwqsqxbZm9pCTW3QK33sZPVulQ8d9Lrl"
KERNEL_NAME="vmlinux"
DISK_NAME="parsec.img"

# ---------------------------------------------------------------- logging ---

if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
    C_RED=$'\033[31m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'
else
    C_RESET=""; C_BOLD=""; C_DIM=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""
fi

log()   { printf '%s==>%s %s\n' "${C_BLUE}${C_BOLD}" "${C_RESET}" "$*"; }
info()  { printf '    %s\n' "$*"; }
dim()   { printf '    %s%s%s\n' "${C_DIM}" "$*" "${C_RESET}"; }
ok()    { printf '    %s✓%s %s\n' "${C_GREEN}" "${C_RESET}" "$*"; }
warn()  { printf '    %s!%s %s\n' "${C_YELLOW}" "${C_RESET}" "$*" >&2; }
die()   { printf '%serror:%s %s\n' "${C_RED}${C_BOLD}" "${C_RESET}" "$*" >&2; exit 1; }

mkdir -p "${LOG_DIR}"
