# SC26 Reproducibility Initiative

## About

This repository functions as an extra source of information on topics
associated with the
[Reproducibility Initiative at SC26.](https://sc26.supercomputing.org/program/papers/reproducibility-initiative/)

## OCEAN Figures 3-5

The OCEAN artifact workflow for the paper's fidelity graphs is under
[`artifacts/`](artifacts):

- Figure 3: LMbench random-memory-access latency;
- Figure 4: STREAM bandwidth versus host count; and
- Figure 5: OSU MPI Allgather latency.

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

## For SC26 Paper Authors

A LaTeX template for the AD/AE Appendices is provided in [for-paper-authors](for-paper-authors).

Also, see the supporting [guidelines](for-paper-authors).

Paper authors should carefully read the instructions on the [SC26 AD/AE Process & Badges page](https://sc26.supercomputing.org/program/papers/reproducibility-appendices-badges/).


## For SC26 Reproducibility Committee Members

See [here](for-reviewers) for the reproducibility report template.
