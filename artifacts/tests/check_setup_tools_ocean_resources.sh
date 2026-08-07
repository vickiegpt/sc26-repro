#!/usr/bin/env bash
set -euo pipefail

ARTIFACTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP_SCRIPT="${ARTIFACTS_DIR}/setup-tools.sh"

QEMU_URL="https://drive.google.com/file/d/19yLZPEI5HN23noVx2m3OsYhJVbuvan1y/view?usp=drive_link"
KERNEL_URL="https://drive.google.com/file/d/1hxHVrcPfoO-PRbWFhYJEala7UVL7hJoy/view?usp=drive_link"

bash -n "${SETUP_SCRIPT}"
grep -Fq "OCEAN_DISK_GDOWN=\"${QEMU_URL}\"" "${SETUP_SCRIPT}"
grep -Fq "OCEAN_KERNEL_GDOWN=\"${KERNEL_URL}\"" "${SETUP_SCRIPT}"
grep -Fq '"${GDOWN}" --fuzzy "${OCEAN_DISK_GDOWN}" -O "${ocean_build_dir}/qemu.img"' "${SETUP_SCRIPT}"
grep -Fq '"${GDOWN}" --fuzzy "${OCEAN_KERNEL_GDOWN}" -O "${ocean_build_dir}/bzImage"' "${SETUP_SCRIPT}"

if grep -Fq 'https://asplos.dev/about/bzImage' "${SETUP_SCRIPT}"; then
    echo "old OCEAN kernel URL remains in setup-tools.sh" >&2
    exit 1
fi
if grep -Fq '1ga5CN3_H1qfReer99w_QcVOYb6R21JHI' "${SETUP_SCRIPT}"; then
    echo "old OCEAN disk-image ID remains in setup-tools.sh" >&2
    exit 1
fi

echo "ok: OCEAN guest resource URLs and download commands"
