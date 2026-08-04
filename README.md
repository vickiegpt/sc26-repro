# SC26 Reproducibility Initiative

## About

This repository functions as an extra source of information on topics
associated with the
[Reproducibility Initiative at SC26.](https://sc26.supercomputing.org/program/papers/reproducibility-initiative/)

## OCEAN and SimCXL Figures 3-5

The artifact workflow for the paper's fidelity graphs is under
[`artifacts/`](artifacts):

- Figure 3: LMbench random-memory-access latency on OCEAN and SimCXL;
- Figure 4: OCEAN STREAM bandwidth versus host count; and
- Figure 5: OCEAN OSU MPI Allgather latency.

Install the plotting dependency and regenerate all three figures with:

```bash
python3 -m pip install -r requirements.txt
./run-experiments.sh
```

The default command uses archived reference CSV files and validates the
paper's qualitative invariants. Each figure directory also provides a
collection wrapper for fresh measurements. We will run the fresh
reproduction campaign on Chameleon Cloud and record the allocated hardware,
image, network, and benchmark runtimes with the resulting raw logs.

Figure 3 has two independent collection paths: OCEAN/SHM runs LMbench inside
an OCEAN guest, while the SimCXL path runs the same sizes and stride through a
pinned gem5/SimCXL configuration. Figures 4 and 5 are OCEAN-only experiments.
The final pinned implementation checkouts belong under [`tools/`](tools).

## For SC26 Paper Authors

A LaTeX template for the AD/AE Appendices is provided in [for-paper-authors](for-paper-authors).

Also, see the supporting [guidelines](for-paper-authors).

Paper authors should carefully read the instructions on the [SC26 AD/AE Process & Badges page](https://sc26.supercomputing.org/program/papers/reproducibility-appendices-badges/).


## For SC26 Reproducibility Committee Members

See [here](for-reviewers) for the reproducibility report template.
