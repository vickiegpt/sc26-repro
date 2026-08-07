#!/usr/bin/env python3
import csv, sys
from collections import defaultdict
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

def main():
    if len(sys.argv) != 3:
        sys.exit("Usage: analyze_fig5.py <csv> <plot>")
    csv_path, plot_path = sys.argv[1], sys.argv[2]
    
    rows = [r for r in csv.DictReader(open(csv_path)) if r["avg_latency_us"] != "blocked"]
    transports = sorted(set(r["transport"] for r in rows))
    
    if not transports:
        sys.exit("FAIL: no valid latency rows for any transport")

    by_t = defaultdict(list)
    for r in rows:
        by_t[r["transport"]].append((int(r["size_bytes"]), float(r["avg_latency_us"])))

    fig, ax = plt.subplots(figsize=(7, 5))
    for t, pts in sorted(by_t.items()):
        pts.sort()
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        ax.plot(xs, ys, marker="o", label=f"OCEAN/{t}")

    ax.set_xscale("log", base=2)
    ax.set_yscale("log")
    ax.set_xlabel("Message size (bytes)")
    ax.set_ylabel("Avg latency (us)")
    ax.set_title("OCEAN Fig 5: osu_allgather latency")
    ax.legend()
    ax.grid(True, which="both", alpha=0.3)
    fig.tight_layout()
    fig.savefig(plot_path, dpi=150)

    print(f"PASS: Fig 5 produced a latency curve for: {', '.join(transports)}")
    sys.exit(0)

if __name__ == "__main__":
    main()
