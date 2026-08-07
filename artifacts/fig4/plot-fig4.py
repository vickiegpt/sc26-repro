#!/usr/bin/env python3
import csv, sys
from collections import defaultdict
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

def main():
    if len(sys.argv) != 3:
        sys.exit("Usage: analyze_fig4.py <csv> <plot>")
    csv_path, plot_path = sys.argv[1], sys.argv[2]
    
    rows = list(csv.DictReader(open(csv_path)))
    if not rows:
        sys.exit("FAIL: no rows collected")

    by_kernel = defaultdict(dict)
    for r in rows:
        by_kernel[r["kernel"]][int(r["hosts"])] = float(r["rate_mb_s"])

    all_ok = True
    fig, ax = plt.subplots(figsize=(7, 5))
    
    for kernel, series in sorted(by_kernel.items()):
        hosts = sorted(series)
        per_host = [series[h] / h for h in hosts]
        declining = all(b <= a * 1.05 for a, b in zip(per_host, per_host[1:]))
        
        print(f"    {kernel}: per-host MB/s = {[round(x) for x in per_host]} ({'declining' if declining else 'NOT declining'})")
        all_ok = all_ok and declining
        ax.plot(hosts, per_host, marker="o", label=kernel)

    ax.set_xlabel("Host count")
    ax.set_ylabel("Per-host bandwidth (MB/s)")
    ax.set_title("OCEAN Fig 4: STREAM bandwidth vs. host count")
    ax.legend()
    ax.grid(True, alpha=0.3)
    fig.tight_layout()
    fig.savefig(plot_path, dpi=150)

    print("PASS: Fig 4 invariant holds" if all_ok else "FAIL: per-host bandwidth did not decline")
    sys.exit(0 if all_ok else 1)

if __name__ == "__main__":
    main()
