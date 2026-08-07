#!/usr/bin/env python3
import csv
import re
from pathlib import Path

import matplotlib.pyplot as plt


ROOT = Path(__file__).resolve().parent
RAW = ROOT / "fig5-osu-diagnostic.raw"
CSV = ROOT / "fig5-osu-diagnostic.csv"
PNG = ROOT / "fig5-osu-diagnostic.png"
PDF = ROOT / "fig5-osu-diagnostic.pdf"
EXPECTED_SIZES = [2**power for power in range(1, 14)]


def load_rows():
    ansi = re.compile(r"\x1b\[[0-9;]*m")
    row_pattern = re.compile(r"^\s*(\d+)\s+([0-9]+(?:\.[0-9]+)?)\s*$")
    rows = []
    for raw_line in RAW.read_text(errors="replace").splitlines():
        match = row_pattern.match(ansi.sub("", raw_line))
        if match:
            rows.append((int(match.group(1)), float(match.group(2))))
    if [size for size, _ in rows] != EXPECTED_SIZES:
        raise SystemExit(f"unexpected OSU sizes: {[size for size, _ in rows]}")
    return rows


def main():
    rows = load_rows()
    with CSV.open("w", newline="") as stream:
        writer = csv.writer(stream)
        writer.writerow(["message_size_bytes", "avg_latency_us", "backend_status"])
        writer.writerows(
            (size, latency, "qemu_tcp_requested_server_mediation_unverified")
            for size, latency in rows
        )

    sizes = [size for size, _ in rows]
    latency = [value for _, value in rows]
    fig, axis = plt.subplots(figsize=(7.2, 4.5))
    axis.plot(sizes, latency, color="#2F6B9A", marker="o", linewidth=2, markersize=5)
    axis.set_xscale("log", base=2)
    axis.set_yscale("log")
    axis.set_xticks(sizes)
    axis.set_xticklabels([f"$2^{{{power}}}$" for power in range(1, 14)])
    axis.set_xlabel("Message size (bytes)")
    axis.set_ylabel("Average latency (µs, log scale)")
    fig.suptitle(
        "OSU MPI Allgather latency (diagnostic)",
        x=0.09,
        y=0.98,
        ha="left",
        fontsize=16,
        weight="bold",
    )
    fig.text(
        0.09,
        0.925,
        "2 bridged QEMU guests, shared DAX shim; QEMU TCP requested, server mediation unverified",
        fontsize=9,
        color="#555555",
        ha="left",
    )
    axis.grid(axis="y", color="#D9DEE3", linewidth=0.8, which="both")
    axis.grid(axis="x", visible=False)
    axis.spines[["top", "right"]].set_visible(False)
    axis.annotate(
        "Shim path changes above 4 KiB",
        xy=(8192, latency[-1]),
        xytext=(500, 180),
        arrowprops={"arrowstyle": "->", "color": "#555555"},
        fontsize=9,
        color="#333333",
    )
    fig.subplots_adjust(left=0.12, right=0.98, bottom=0.16, top=0.84)
    fig.savefig(PNG, dpi=200)
    fig.savefig(PDF)


if __name__ == "__main__":
    main()
