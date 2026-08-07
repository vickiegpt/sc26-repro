#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${SCRIPT_DIR}/data"

echo " Phase 1: Running OCEAN lat_mem_rd               "
echo "================================================="
"${SCRIPT_DIR}/run-fig3.sh" "$@"

echo ""
echo " Phase 2: Running SimCXL lat_mem_rd              "
echo "================================================="
"${SCRIPT_DIR}/run-fig3-simcxl.sh"

echo ""
echo " Phase 3: Generating Comparative Graph           "
echo "================================================="
PLOT="${DATA_DIR}/lat_mem_rd_combined.png"

# We pass all potential data files to the graphing script.
# (If hw_cxl_asic.csv doesn't exist yet, it will safely skip it.)
python3 "${SCRIPT_DIR}/plot-fig3.py" \
    --plot "${PLOT}" \
    --ocean "${DATA_DIR}/ocean.csv" \
    --sim-asic "${DATA_DIR}/simcxl_asic.csv" \
    --sim-fpga "${DATA_DIR}/simcxl_fpga.csv" \
    --hw-asic "${DATA_DIR}/hw_cxl_asic.csv"

echo "================================================="
echo " Pipeline complete! Check data in ${DATA_DIR}/   "
echo "================================================="
