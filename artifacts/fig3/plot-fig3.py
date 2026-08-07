#!/usr/bin/env python3
import argparse
import csv
import sys
from pathlib import Path
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

def main():
    parser = argparse.ArgumentParser(description="Graph multiple lat_mem_rd CSV outputs.")
    parser.add_argument("--plot", required=True, type=Path, help="Output PNG path")
    parser.add_argument("--ocean", type=Path, help="Path to ocean.csv")
    parser.add_argument("--sim-asic", type=Path, help="Path to simcxl_asic.csv")
    parser.add_argument("--sim-fpga", type=Path, help="Path to simcxl_fpga.csv")
    parser.add_argument("--hw-asic", type=Path, help="Path to hw_cxl_asic.csv")
    args = parser.parse_args()

    datasets = [
        ("OCEAN", args.ocean),
        ("SimCXL ASIC", args.sim_asic),
        ("SimCXL FPGA", args.sim_fpga),
        ("Real HW ASIC", args.hw_asic)
    ]

    fig, ax = plt.subplots(figsize=(8, 6))
    plotted = 0

    for label, path in datasets:
        if path and path.is_file():
            rows = list(csv.DictReader(path.open()))
            by_size = {}
            for r in rows:
                if "size_mb" in r and "latency_ns" in r:
                    by_size.setdefault(float(r["size_mb"]), []).append(float(r["latency_ns"]))
            
            if not by_size:
                continue

            sizes = sorted(by_size.keys())
            means = [sum(by_size[s]) / len(by_size[s]) for s in sizes]
            
            print(f"Loaded {label}: Max size {sizes[-1]:.0f}MB -> {means[-1]:.1f} ns latency")
            ax.plot(sizes, means, marker="o", markersize=4, label=label)
            plotted += 1

    if plotted == 0:
        print("ERROR: No valid data found to plot!")
        sys.exit(1)

    ax.set_xscale("log", base=2)
    ax.set_xlabel("Array size (MB)")
    ax.set_ylabel("Latency (ns)")
    ax.set_title("CXL Memory Latency Comparison (lat_mem_rd)")
    ax.grid(True, which="both", alpha=0.3)
    ax.legend()
    fig.tight_layout()
    
    args.plot.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(args.plot, dpi=150)
    print(f"\nSUCCESS: Graph saved to {args.plot}")

if __name__ == "__main__":
    sys.exit(main())

