# Reproducing Figures 3--9

The artifact is organized by paper figure:

```text
artifacts/
├── fig3/  # OCEAN + SimCXL LMbench random-access latency
├── fig4/  # OCEAN STREAM bandwidth versus host count
├── fig5/  # OCEAN OSU MPI Allgather latency
├── fig6/  # OCEAN/Tigon TPC-C HCC coverage
├── fig7/  # OCEAN/Tigon YCSB read/write sweep
├── fig8/  # OCEAN/GROMACS placement-policy sweep
└── fig9/  # physical-CXL LogP calibration
```

Each directory contains:

- `data/reference.csv`: values used to recreate the submitted-paper graph;
- `collect.py` and `run-experiment.sh`: a fresh-measurement path;
- `plot.py`: deterministic PDF and PNG generation;
- `validate.py`: schema and paper-invariant checks; and
- `README.md`: benchmark-specific setup and commands.

The systems are deliberately separated by runner contract. Figure 3 collects
both OCEAN/SHM and SimCXL/gem5 measurements. Figures 4 and 5 exercise OCEAN's
multi-host transport and memory-pool paths and do not invoke SimCXL.

From the repository root:

```bash
python3 -m pip install -r requirements.txt
./run-experiments.sh
```

This regenerates and validates all three graphs using archived reference
data. Select individual figures with `--figures 3,5`.

To collect new measurements, read the selected figure's README and run:

```bash
./run-experiments.sh --figures 3 --mode collect --data results
./run-experiments.sh --figures 3 --mode all --data results
```

Fresh measurements for Figures 3--8 will be reproduced on Chameleon Cloud.
The site-specific runner scripts will provision the allocated nodes and
record the Chameleon lease, hardware type, image, network configuration, and
wall time alongside the raw benchmark logs.

Figures 6--9 use the same runner contract as the first three workflows but
require their author-supplied workload inputs and orchestration entrypoints.
Figure 9 additionally requires the two-host physical-CXL testbed. Their
implementation is pinned in the repository's ``Ocean`` submodule. Run
``Ocean/script/reproduce_figures_6_9.py`` for prerequisite checks, collection,
validation, and plotting. Successful runs are stored under
``Ocean/artifact/figures_6_9/<run-id>/``; no measured Figures 6--9 result bundle
is committed until those external prerequisites are exercised.

## Provenance of the archived CSV files

- Figure 3 was recovered from the vector paths embedded in `OCEAN.pdf`.
- Figure 4 was digitized from the raster graph embedded in `OCEAN.pdf`.
- Figure 5 was recovered from the vector paths embedded in `OCEAN.pdf`.

These CSV files make the graph-generation step reproducible, but they are not
a substitute for the original raw benchmark logs. Before the final artifact
archive is frozen, replace the digitized Figure 4 values and, ideally, all
three reference CSV files with author-supplied aggregated raw data while
retaining the raw logs in a DOI-backed archive.
