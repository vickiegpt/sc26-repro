# Figure 5 TCP attempt: result and proof boundary

## Outcome

The two-VM OSU MPI Allgather diagnostic completed for message sizes 2 B through
8192 B. It is **not** a validated reproduction of the OCEAN TCP curve in the
paper's Figure 5.

Both QEMU processes were launched with CXLMemSim TCP mode requested, and both
consoles reported:

```text
CXL Type3: Initializing CXLMemSim integration
CXL Type3: CXLMemSim TCP mode - 127.0.0.1:9999
```

However, the server log contains only TCP initialization and the listening
message. A live socket check after the benchmark showed the server listening on
port 9999 with no established connection. No server-side memory requests were
recorded. Therefore, this run proves a two-guest shared-DAX MPI-shim path, but
does not prove that guest DAX traffic traversed the CXLMemSim TCP backend.

## Topology and command

- Guests: `node0` (`192.168.100.10`) and `node1` (`192.168.100.11`)
- QEMU images: `qemu.img` and `qemu1.img`
- Guest CXL device: `/dev/dax0.0`, 250 MiB in each guest
- MPI: Open MPI 5.0.3, one rank per guest
- Benchmark: OSU MPI Allgather latency v5.3
- Shared shim: identical `/root/libmpi_cxl_shim_fig5.so` on both guests

```sh
timeout 300 mpirun --allow-run-as-root -np 2 \
  --hostfile /root/fig5-hostfile \
  -x CXL_DAX_PATH=/dev/dax0.0 \
  -x CXL_DAX_RESET=1 \
  -x LD_PRELOAD=/root/libmpi_cxl_shim_fig5.so \
  -x GLIBC_TUNABLES=glibc.cpu.hwcaps=-AVX,-AVX2,-AVX512F,-AVX_Fast_Unaligned_Load \
  /root/osu-micro-benchmarks/mpi/collective/osu_allgather -m 2:8192
```

## Measured diagnostic data

| Message size (B) | Average latency (us) |
|---:|---:|
| 2 | 59.37 |
| 4 | 61.50 |
| 8 | 73.28 |
| 16 | 88.78 |
| 32 | 90.53 |
| 64 | 124.06 |
| 128 | 183.87 |
| 256 | 303.23 |
| 512 | 529.42 |
| 1024 | 1091.26 |
| 2048 | 2187.23 |
| 4096 | 3934.58 |
| 8192 | 60.17 |

The sharp drop at 8192 B is an implementation-path boundary: the shim's inline
shared-DAX optimization applies only below 4 KiB and the larger transfer falls
back to another path. It must not be interpreted as an OCEAN TCP trend.

## Artifacts

- `fig5-osu-diagnostic.raw`: complete two-rank benchmark output
- `fig5-osu-diagnostic.csv`: parsed values, explicitly marked unverified
- `fig5-osu-diagnostic.png` and `.pdf`: diagnostic visualization
- `plot_fig5_diagnostic.py`: parser and plot generator
- `fig5-server-tcp-b.log`: TCP server log
- `fig5-vm0-tap-tcp-c-console.log`, `fig5-vm1-tap-tcp-c-console.log`: QEMU consoles

Reproducing the original Figure 5 still requires a QEMU/CXL memory path that
demonstrably emits requests to the TCP server, followed by the paper's RDMA and
real-CXL comparison series under matched OSU settings.
