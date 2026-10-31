#!/usr/bin/env bash
# ============================================================
# run_fmax.sh  —  Open-source FPGA flow for riscv_pipeline
#
# Target : Lattice ECP5 LFE5U-25F, CABGA381 (e.g. ULX3S board)
# Tools  : Yosys (synth_ecp5) + nextpnr-ecp5
#
# The core is built with FPGA_PROG_PORT defined, which gives the
# instruction memory a program-load write port. Without it the
# instruction ROM has no contents and synthesis removes the core.
#
# Usage  : synth/run_fmax.sh [build-dir] [seeds...]
#          defaults: build dir synth/build, seeds 1 2 3
#          EXTRA_DEFINES="-DNO_MAC_EXT" builds the core without the MAC
#          instruction, to measure the extension's cost
# Output : utilisation and per-seed Fmax, plus summary.txt
# ============================================================
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-$ROOT/synth/build}
shift || true
SEEDS=${*:-1 2 3}
mkdir -p "$OUT"

SRCS="ALU.v Forward_units.v Hazard_units.v Imem.v RegFile.v control.v \
      dmem.v lsu_align.v mul_pipe.v pipeline_reg.v Riscv_pipeline.v"

cd "$ROOT"
yosys -q -l "$OUT/yosys.log" -p "
    read_verilog -DFPGA_PROG_PORT ${EXTRA_DEFINES:-} $SRCS;
    synth_ecp5 -top riscv_pipeline -json $OUT/top.json"

for s in $SEEDS; do
    nextpnr-ecp5 --25k --package CABGA381 --json "$OUT/top.json" \
                 --freq 25 --seed "$s" --timing-allow-fail \
                 > "$OUT/pnr_seed$s.log" 2>&1 &
done
wait

{
    echo "Device: LFE5U-25F CABGA381, seeds: $SEEDS ${EXTRA_DEFINES:-}"
    grep -E "TRELLIS_COMB:|TRELLIS_FF:|TRELLIS_RAMW:|DP16KD:|MULT18X18D:" \
         "$OUT/pnr_seed${SEEDS%% *}.log" | head -5 | sed 's/^Info: *//'
    for s in $SEEDS; do
        f=$(grep "Max frequency for clock" "$OUT/pnr_seed$s.log" | tail -1 \
            | sed -E 's/.*: ([0-9.]+) MHz.*/\1/')
        echo "seed $s: Fmax $f MHz"
    done
} | tee "$OUT/summary.txt"
