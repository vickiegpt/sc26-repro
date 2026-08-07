#!/usr/bin/env bash
#
# Set up the tooling needed to run the reproduce-*.sh experiment scripts:
# submodules, build dependencies, the gem5 binary, and the kernel/disk image
# resources. Run this once (or let reproduce-fig3.sh run it for you); the
# experiment scripts assume everything here is already in place.
#
# Stages (run all by default except `deps`, which needs sudo — pick with
# --stage):
#   submodules  git submodule update --init --recursive
#   deps        apt-get the build dependencies listed in SimCXL's README
#   build       scons build/X86/gem5.opt
#   resources   fetch vmlinux + parsec.img from the SimCXL Google Drive folder
#               into ./resources, decompressing the disk image if needed
#   ocean       setup OCEAN host dependencies and download OCEAN disk/kernel
#
# Usage:
#   ./setup-tools.sh                  # submodules, build, resources, ocean
#   ./setup-tools.sh --stage deps     # apt-get build deps (needs sudo)
#   ./setup-tools.sh --stage build --jobs 32
#
set -euo pipefail

ARTIFACTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${ARTIFACTS_DIR}/scripts/common.sh"

ALL_STAGES="submodules deps build resources ocean"
STAGES="submodules build resources ocean"   # `deps` is opt-in (needs sudo)
JOBS="$(nproc)"
REUSE_LOCAL=1
FORCE_FETCH=0
FORCE_BUILD=0
GDOWN=""

# --- OCEAN Resource Configuration ---
OCEAN_KERNEL_GDOWN="https://drive.google.com/file/d/1hxHVrcPfoO-PRbWFhYJEala7UVL7hJoy/view?usp=drive_link"
OCEAN_DISK_GDOWN="https://drive.google.com/file/d/19yLZPEI5HN23noVx2m3OsYhJVbuvan1y/view?usp=drive_link"

has_stage() { [[ " ${STAGES} " == *" $1 "* ]]; }

# ------------------------------------------------------------------- args ---

usage() {
    # Print the header comment block (everything after the shebang, up to the
    # first non-comment line).
    awk 'NR==1 {next} /^#/ {sub(/^# ?/, ""); print; next} {exit}' "${BASH_SOURCE[0]}"
    cat <<EOF

Options:
  --stage LIST      Comma/space separated subset of: ${ALL_STAGES}
  --jobs N          Parallel scons jobs (default: nproc = ${JOBS})
  --no-reuse-local  Always download resources instead of reusing an existing
                    ${KERNEL_NAME}/${DISK_NAME} already sitting in artifacts/
  --force-fetch     Re-download resources even if ./resources already has them
  --force-build     Rebuild gem5.opt even if the binary already exists
  -h, --help        This message
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --stage)          STAGES="${2//,/ }"; shift 2 ;;
        --stage=*)        STAGES="${1#*=}"; STAGES="${STAGES//,/ }"; shift ;;
        --jobs|-j)        JOBS="$2"; shift 2 ;;
        --jobs=*)         JOBS="${1#*=}"; shift ;;
        --no-reuse-local) REUSE_LOCAL=0; shift ;;
        --force-fetch)    FORCE_FETCH=1; shift ;;
        --force-build)    FORCE_BUILD=1; shift ;;
        -h|--help)        usage; exit 0 ;;
        *)                die "unknown argument: $1 (try --help)" ;;
    esac
done

for s in ${STAGES}; do
    [[ " ${ALL_STAGES} " == *" ${s} "* ]] || die "unknown stage: ${s} (valid: ${ALL_STAGES})"
done

# ------------------------------------------------------- stage: submodules ---

stage_submodules() {
    log "Checking out submodules"
    [[ -f "${REPO_ROOT}/.gitmodules" ]] || die "no .gitmodules at ${REPO_ROOT}"

    git -C "${REPO_ROOT}" submodule update --init --recursive

    local path
    while read -r path; do
        [[ -n "${path}" ]] || continue
        if [[ -z "$(ls -A "${REPO_ROOT}/${path}" 2>/dev/null)" ]]; then
            die "submodule ${path} is still empty after update --init"
        fi
        ok "${path}"
    done < <(git -C "${REPO_ROOT}" config --file .gitmodules --get-regexp '^submodule\..*\.path$' | awk '{print $2}')
}

# ------------------------------------------------------------- stage: deps ---

stage_deps() {
    log "Installing build dependencies (SimCXL README)"
    sudo apt update
    sudo apt-get install -y build-essential git m4 scons zlib1g zlib1g-dev \
        libprotobuf-dev protobuf-compiler libprotoc-dev libgoogle-perftools-dev \
        python3-dev python-is-python3 libboost-all-dev pkg-config libpng-dev
    # Not in the README, but needed to bootstrap gdown for the resources stage
    # on PEP-668 ("externally managed") distros.
    sudo apt-get install -y python3-venv python3-pip || \
        warn "could not install python3-venv/python3-pip; the resources stage may not be able to install gdown"
    ok "apt dependencies installed"
}

# ------------------------------------------------------------ stage: build ---

stage_build() {
    log "Building SimCXL (gem5.opt, X86)"
    [[ -d "${SIMCXL_DIR}" ]] || die "${SIMCXL_DIR} missing — run the submodules stage first"

    if [[ -x "${SIMCXL_DIR}/${GEM5_BIN_REL}" && "${FORCE_BUILD}" -eq 0 ]]; then
        ok "${GEM5_BIN_REL} already built (--force-build to rebuild)"
        return
    fi

    command -v scons >/dev/null || die "scons not found — run ./setup-tools.sh --stage deps, or apt install scons"

    local log_file="${LOG_DIR}/build.log"
    info "this can take 1-2 hours; -j${JOBS}; log: ${log_file}"
    if ! ( cd "${SIMCXL_DIR}" && scons "${GEM5_BIN_REL}" -j"${JOBS}" ) 2>&1 | tee "${log_file}"; then
        die "scons failed; see ${log_file}"
    fi

    [[ -x "${SIMCXL_DIR}/${GEM5_BIN_REL}" ]] || die "build finished but ${GEM5_BIN_REL} is missing; see ${log_file}"
    ok "built ${GEM5_BIN_REL}"
}

# -------------------------------------------------------- stage: resources ---

# Decompress $1 in place if it is a recognised archive; echo the resulting path.
decompress_if_needed() {
    local src="$1" base
    case "${src}" in
        *.tar.gz|*.tgz|*.tar.xz|*.tar.zst|*.tar.bz2)
            dim "extracting $(basename "${src}")" >&2
            tar -xf "${src}" -C "$(dirname "${src}")"
            ;;
        *.gz)   base="${src%.gz}";  dim "gunzip $(basename "${src}")" >&2;  gzip -dk  -- "${src}" ;;
        *.zst)  base="${src%.zst}"; dim "unzstd $(basename "${src}")" >&2;  zstd -dk  -- "${src}" ;;
        *.xz)   base="${src%.xz}";  dim "unxz $(basename "${src}")" >&2;    xz  -dk   -- "${src}" ;;
        *.bz2)  base="${src%.bz2}"; dim "bunzip2 $(basename "${src}")" >&2; bzip2 -dk -- "${src}" ;;
        *.zip)  dim "unzip $(basename "${src}")" >&2; unzip -o -q -- "${src}" -d "$(dirname "${src}")" ;;
        *)      printf '%s\n' "${src}"; return 0 ;;
    esac
    [[ -n "${base:-}" ]] && printf '%s\n' "${base}"
    return 0
}

# Locate or install gdown, setting GDOWN to a runnable command. Distros that
# mark the system Python "externally managed" (PEP 668) reject a plain
# `pip install --user`, so fall back through a venv and then an explicit
# override before giving up.
ensure_gdown() {
    if command -v gdown >/dev/null; then
        GDOWN="$(command -v gdown)"
        dim "using ${GDOWN}"
        return
    fi

    local venv="${ARTIFACTS_DIR}/.venv-tools"
    if [[ -x "${venv}/bin/gdown" ]]; then
        GDOWN="${venv}/bin/gdown"
        dim "using ${GDOWN}"
        return
    fi

    info "gdown not found; installing"

    if python3 -m venv "${venv}" >/dev/null 2>&1 && \
       "${venv}/bin/pip" install --quiet --upgrade gdown >/dev/null 2>&1 && \
       [[ -x "${venv}/bin/gdown" ]]; then
        GDOWN="${venv}/bin/gdown"
        ok "installed gdown into ${venv}"
        return
    fi
    rm -rf "${venv}"

    if python3 -m pip install --user --quiet gdown >/dev/null 2>&1; then
        GDOWN="$(command -v gdown || printf '%s' "${HOME}/.local/bin/gdown")"
        [[ -x "${GDOWN}" ]] && { ok "installed gdown (--user)"; return; }
    fi

    if python3 -m pip install --user --quiet --break-system-packages gdown >/dev/null 2>&1; then
        GDOWN="$(command -v gdown || printf '%s' "${HOME}/.local/bin/gdown")"
        [[ -x "${GDOWN}" ]] && { ok "installed gdown (--break-system-packages)"; return; }
    fi

    die "could not install gdown. Install it yourself, e.g.
        sudo apt install python3-venv && ${BASH_SOURCE[0]} --stage deps
      or 'pipx install gdown', then re-run.
      Alternatively download ${DRIVE_URL}
      manually and put ${KERNEL_NAME} and ${DISK_NAME} in ${RESOURCES_DIR}/"
}

stage_resources() {
    log "Fetching kernel + disk image into ./resources"
    mkdir -p "${RESOURCES_DIR}"

    local kernel="${RESOURCES_DIR}/${KERNEL_NAME}"
    local disk="${RESOURCES_DIR}/${DISK_NAME}"

    if [[ "${FORCE_FETCH}" -eq 0 && -s "${kernel}" && -s "${disk}" ]]; then
        ok "${KERNEL_NAME} and ${DISK_NAME} already present (--force-fetch to re-download)"
        return
    fi

    # Adopt a copy already sitting in artifacts/ rather than re-pulling 25 GB.
    # Same filesystem, so this is an instant rename, not a 25 GB copy — and it
    # leaves resources/ holding the real files rather than symlinks.
    if [[ "${REUSE_LOCAL}" -eq 1 && "${FORCE_FETCH}" -eq 0 ]]; then
        local name
        for name in "${KERNEL_NAME}" "${DISK_NAME}"; do
            if [[ ! -e "${RESOURCES_DIR}/${name}" && -s "${ARTIFACTS_DIR}/${name}" ]]; then
                mv "${ARTIFACTS_DIR}/${name}" "${RESOURCES_DIR}/${name}"
                warn "moved existing ${name} from artifacts/ into resources/; pass --no-reuse-local to download a fresh copy instead"
            fi
        done
        if [[ -s "${kernel}" && -s "${disk}" ]]; then
            ok "resources satisfied from local copies"
            return
        fi
    fi

    ensure_gdown

    local stage_dir="${RESOURCES_DIR}/.download"
    mkdir -p "${stage_dir}"
    info "downloading ${DRIVE_URL}"
    info "this is tens of GB and will take a while; log: ${LOG_DIR}/gdown.log"
    "${GDOWN}" --folder "${DRIVE_URL}" --continue -O "${stage_dir}" 2>&1 | tee "${LOG_DIR}/gdown.log" \
        || die "gdown failed; Google Drive may be rate-limiting. Re-run to resume, or download manually into ${RESOURCES_DIR}"

    # gdown --folder nests everything under the Drive folder's name; flatten it.
    local f
    while IFS= read -r -d '' f; do
        mv -f "${f}" "${RESOURCES_DIR}/$(basename "${f}")"
    done < <(find "${stage_dir}" -type f -print0)
    rm -rf "${stage_dir}"

    # The disk image ships compressed.
    if [[ ! -s "${disk}" ]]; then
        local archive
        archive="$(find "${RESOURCES_DIR}" -maxdepth 1 -type f -name "${DISK_NAME}.*" | head -n1)"
        [[ -n "${archive}" ]] || archive="$(find "${RESOURCES_DIR}" -maxdepth 1 -type f \
            \( -name '*.img.gz' -o -name '*.img.zst' -o -name '*.img.xz' -o -name '*.img.bz2' \
               -o -name '*.tar.gz' -o -name '*.tgz' -o -name '*.zip' \) | head -n1)"
        [[ -n "${archive}" ]] || die "no ${DISK_NAME} and no archive to unpack in ${RESOURCES_DIR}"

        info "decompressing $(basename "${archive}") (needs ~25 GB free)"
        decompress_if_needed "${archive}" >/dev/null

        if [[ ! -s "${disk}" ]]; then
            # Archive may have unpacked to a differently-named .img.
            local found
            found="$(find "${RESOURCES_DIR}" -maxdepth 2 -type f -name '*.img' | head -n1)"
            [[ -n "${found}" ]] || die "decompressed ${archive} but found no .img in ${RESOURCES_DIR}"
            [[ "${found}" == "${disk}" ]] || mv -f "${found}" "${disk}"
        fi
        ok "disk image ready: ${disk}"
    fi

    [[ -s "${kernel}" ]] || die "kernel ${KERNEL_NAME} not found in ${RESOURCES_DIR} after download"
    [[ -s "${disk}"   ]] || die "disk image ${DISK_NAME} not found in ${RESOURCES_DIR} after download"

    ok "$(du -h --dereference "${kernel}" | cut -f1)    ${kernel}"
    ok "$(du -h --dereference "${disk}"   | cut -f1)    ${disk}"
}

# ------------------------------------------------------------ stage: ocean ---
stage_ocean() {
    log "Setting up OCEAN"
    local ocean_dir="${ARTIFACTS_DIR}/tools/OCEAN"
    local ocean_build_dir="${ocean_dir}/build"

    if [[ ! -d "${ocean_dir}" ]]; then
        die "OCEAN directory not found at ${ocean_dir} — did the submodules stage run?"
    fi

    log "Running OCEAN setup_host.sh"
    # This may prompt for sudo privileges depending on what setup_host.sh does
    bash "${ocean_dir}/script/setup_host.sh"

    log "Preparing OCEAN build directory: ${ocean_build_dir}"
    mkdir -p "${ocean_build_dir}"

    log "Building OCEAN application"
    # Run the compile steps inside a subshell to preserve the working directory
    (
        cd "${ocean_build_dir}"
        cmake .. -DSERVER_MODE=ON -DCMAKE_CXX_COMPILER=g++-13
        make -j"${JOBS}"
    ) || die "Failed to build OCEAN application."

    if [[ "${FORCE_FETCH}" -eq 0 && -s "${ocean_build_dir}/bzImage" && -s "${ocean_build_dir}/qemu.img" ]]; then
        ok "OCEAN resources already present in ${ocean_build_dir} (--force-fetch to re-download)"
        return
    fi

    log "Fetching OCEAN guest kernel and disk image via gdown"
    if [[ -z "${OCEAN_KERNEL_GDOWN}" ]]; then
        die "OCEAN_KERNEL_GDOWN is not set. Aborting."
    fi
    if [[ -z "${OCEAN_DISK_GDOWN}" ]]; then
        die "OCEAN_DISK_GDOWN is not set. Aborting."
    fi
    ensure_gdown

    "${GDOWN}" --fuzzy "${OCEAN_KERNEL_GDOWN}" -O "${ocean_build_dir}/bzImage" || die "Failed to download OCEAN kernel."
    "${GDOWN}" --fuzzy "${OCEAN_DISK_GDOWN}" -O "${ocean_build_dir}/qemu.img" || die "Failed to download OCEAN disk image."

    ok "OCEAN setup complete. Check ${ocean_build_dir} for downloaded files."
}

# ------------------------------------------------------------------- main ---

log "artifacts: ${ARTIFACTS_DIR}"
dim "stages: ${STAGES}"

for stage in ${ALL_STAGES}; do
    has_stage "${stage}" || continue
    "stage_${stage}"
done

log "Done."
