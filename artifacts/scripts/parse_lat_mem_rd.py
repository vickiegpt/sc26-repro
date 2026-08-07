#!/usr/bin/env python3
"""Extract lat_mem_rd latency tables from a gem5 console log into CSV.

lmbench's `lat_mem_rd` prints, after a `"stride=N` header, one
`<array size in MB> <latency in ns>` pair per line.  SimCXL's guest scripts
fence each invocation with `=====... start=====` / `=====... finish=====`
markers, but we do not rely on them: any `"stride=` header starts a table and
the first non-conforming line ends it.

Usage:
    parse_lat_mem_rd.py <board.pc.com_1.device> <out.csv> [--table N]
"""

from __future__ import annotations

import argparse
import csv
import re
import sys
from pathlib import Path

STRIDE_RE = re.compile(r'"?stride\s*=\s*(\d+)')
ROW_RE = re.compile(r"^\s*(\d+\.\d+)\s+(\d+\.\d+)\s*$")
# e.g. "=====CXL lat_mem_rd -t -N 2 1024 64 start=====" -> max size 1024 MB
INVOCATION_RE = re.compile(
    r"lat_mem_rd\b[^\n]*?\s(\d+)\s+(\d+)\s*(?:start)?=*\s*$", re.MULTILINE)


def expected_max_mb(text: str) -> float | None:
    """The largest array size lat_mem_rd was asked for, per its command line."""
    sizes = [int(m.group(1)) for m in INVOCATION_RE.finditer(text)]
    return float(max(sizes)) if sizes else None


def parse_tables(text: str) -> list[dict]:
    """Return every lat_mem_rd table found in `text`, in file order."""
    tables: list[dict] = []
    current: dict | None = None

    for line in text.splitlines():
        header = STRIDE_RE.search(line)
        if header:
            # A new stride header always begins a fresh table.
            if current and current["rows"]:
                tables.append(current)
            current = {"stride": int(header.group(1)), "rows": []}
            continue

        if current is None:
            continue

        row = ROW_RE.match(line)
        if row:
            current["rows"].append((float(row.group(1)), float(row.group(2))))
        elif current["rows"]:
            # Table ended (blank line, finish marker, shell prompt, ...).
            tables.append(current)
            current = None

    if current and current["rows"]:
        tables.append(current)

    return tables


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input", type=Path, help="gem5 board.pc.com_1.device log")
    ap.add_argument("output", type=Path, help="CSV file to write")
    ap.add_argument("--table", type=int, default=0,
                    help="0-based index of the table to emit when the log "
                         "contains more than one (default: 0)")
    ap.add_argument("--list", action="store_true",
                    help="list the tables found and exit without writing")
    args = ap.parse_args()

    if not args.input.is_file():
        print(f"error: no such file: {args.input}", file=sys.stderr)
        return 1

    text = args.input.read_text(errors="replace")
    tables = parse_tables(text)

    if not tables:
        print(f"error: no lat_mem_rd table found in {args.input}", file=sys.stderr)
        print("hint: the run may not have reached the benchmark, or it was "
              "killed before lat_mem_rd finished.", file=sys.stderr)
        return 2

    if args.list:
        for i, t in enumerate(tables):
            lo = t["rows"][0][0]
            hi = t["rows"][-1][0]
            print(f"[{i}] stride={t['stride']} rows={len(t['rows'])} "
                  f"size={lo:g}..{hi:g} MB")
        return 0

    if args.table >= len(tables):
        print(f"error: requested table {args.table} but only {len(tables)} "
              f"found in {args.input}", file=sys.stderr)
        return 2

    table = tables[args.table]

    # A run that was killed mid-benchmark still leaves a well-formed but short
    # table behind; that would silently become a truncated CSV.
    wanted = expected_max_mb(text)
    reached = table["rows"][-1][0]
    if wanted is not None and reached < wanted:
        print(f"warning: {args.input.name}: table stops at {reached:g} MB but "
              f"lat_mem_rd was asked for {wanted:g} MB — the run looks "
              f"incomplete", file=sys.stderr)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["size_mb", "latency_ns"])
        for size_mb, latency_ns in table["rows"]:
            w.writerow([f"{size_mb:.5f}", f"{latency_ns:.3f}"])

    print(f"wrote {len(table['rows'])} rows (stride={table['stride']}) "
          f"-> {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
