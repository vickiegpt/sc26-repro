#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIMCXL_DIR="${SCRIPT_DIR}/../tools/SimCXL"
DATA_DIR="${SCRIPT_DIR}/data"
PARSE_SCRIPT="${SCRIPT_DIR}/../scripts/parse_lat_mem_rd.py"

mkdir -p "${DATA_DIR}"

# Ensure we're in the SimCXL directory before executing gem5
cd "${SIMCXL_DIR}"

echo "Starting SimCXL ASIC simulation..."
build/X86/gem5.opt -d "output/fs_lmbench_cxl_ASIC" configs/example/gem5_library/x86-cxl-type3-with-classic.py \
    --is_asic True --test_cmd lmbench_cxl.sh --cpu_type TIMING

echo "Starting SimCXL FPGA simulation..."
build/X86/gem5.opt -d "output/fs_lmbench_cxl_FPGA" configs/example/gem5_library/x86-cxl-type3-with-classic.py \
    --is_asic False --test_cmd lmbench_cxl.sh --cpu_type TIMING

echo "Parsing SimCXL outputs to CSV..."
# Assuming parse_lat_mem_rd.py takes input_file and output_csv as arguments.
# If its argument order is different, adjust the positional variables below.

if [[ -f "${PARSE_SCRIPT}" ]]; then
    python3 "${PARSE_SCRIPT}" "output/fs_lmbench_cxl_ASIC/board.pc.com_1.device" "${DATA_DIR}/simcxl_asic.csv"
    python3 "${PARSE_SCRIPT}" "output/fs_lmbench_cxl_FPGA/board.pc.com_1.device" "${DATA_DIR}/simcxl_fpga.csv"
    echo "SimCXL data parsing complete! CSVs saved to ${DATA_DIR}"
else
    echo "WARNING: Parser script not found at ${PARSE_SCRIPT}!"
    echo "Raw outputs are located in ${SIMCXL_DIR}/output/fs_lmbench_cxl_{ASIC,FPGA}/board.pc.com_1.device"
    exit 1
fi
