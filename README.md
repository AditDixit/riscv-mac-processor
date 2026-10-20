# RISC-V 32-bit Pipelined Processor with MAC Acceleration Unit

5-stage pipelined RV32I processor in Verilog with a custom MAC instruction (`rd = rd + rs1 × rs2`) in the RISC-V custom-0 opcode space. Includes load-use hazard detection, branch/jump flushes, EX-EX and MEM-EX data forwarding, and a benchmark suite (dot product, FIR, matrix multiply) comparing the MAC instruction against `mul` + `add`: **1.08× to 1.25× fewer cycles** on loop-based kernels, 1.89× on the straight-line 8-element dot product.

## Benchmark Results

### Straight-line dot product (`tb_benchmark.v`)

Dot product of A = [1..8] and B = [8..1] (result 120), fully unrolled, operands already in registers:

| | Standard (mul + add) | MAC accelerated |
|---|---|---|
| Instructions | 16 | 8 |
| Cycles | 17 | 9 |
| **Speedup** | 1.00× | **1.89×** |

This is the best case: only arithmetic, no loads, no loop control.

### Kernels with loads and loops (`verif/bench.py`)

Real kernels have to load operands and run a loop, and those instructions are the same for both versions, so the whole-program gain is smaller. Each program below is assembled from source, run on the RTL pipeline, and cross-checked against both a reference instruction-set simulator and an independent Python computation of the answer (all 10 match).

| Benchmark | mul+add instrs | mul+add cycles | MAC instrs | MAC cycles | Speed-up |
|---|---|---|---|---|---|
| dot product, N=8 (loop) | 52 | 77 | 44 | 69 | 1.12× |
| dot product, N=16 (loop) | 100 | 149 | 84 | 133 | 1.12× |
| dot product, N=32 (loop) | 196 | 293 | 164 | 261 | 1.12× |
| dot product, N=64 (loop) | 388 | 581 | 324 | 517 | 1.12× |
| dot product, N=16 (unrolled ×4) | 76 | 85 | 60 | 69 | 1.23× |
| dot product, N=64 (unrolled ×4) | 292 | 325 | 228 | 261 | 1.25× |
| FIR, 32 outputs × 8 taps | 1986 | 2755 | 1730 | 2499 | 1.10× |
| FIR, 32 outputs × 16 taps | 3778 | 5315 | 3266 | 4803 | 1.11× |
| matrix multiply 4×4 | 639 | 832 | 575 | 768 | 1.08× |
| matrix multiply 8×8 | 4571 | 6108 | 4059 | 5596 | 1.09× |

Cycles are counted from reset release until the final `jal x0, 0` reaches the EX stage. The MAC saves exactly one instruction (and one cycle) per multiply-accumulate, so the speed-up is bounded by the fraction of the program that is the multiply-add itself; unrolling raises it, and the pipeline's load-use and branch penalties are paid equally by both versions.

## Architecture

```
IF → ID → EX → MEM → WB
          ↑
    MAC Unit (custom-0 opcode)
```

- **Hazard detection:** load-use stalls (including a load feeding a MAC's accumulator register) and branch/jump flushes
- **Data forwarding:** EX-EX and MEM-EX bypass paths, plus an accumulator bypass for back-to-back MACs
- **MAC instruction:** `rd = rd + (rs1 × rs2)` in the RISC-V custom-0 opcode space. The register file has a dedicated third read port so the MAC can read its own `rd` as the accumulator.

## File Structure

```
├── Imem.v                Instruction memory (256×32, loads program.hex)
├── dmem.v                Data memory (256×32, word access only)
├── RegFile.v             32×32 register file (2 read ports + accumulator read port)
├── ALU.v                 ALU: all RV32I ops + MUL
├── control.v             Main decoder + ALU decoder + imm_gen
├── pipeline_reg.v        IF/ID, ID/EX, EX/MEM, MEM/WB registers
├── Hazard_units.v        Stall and flush logic
├── Forward_units.v       EX-EX and MEM-EX forwarding
├── riscv_single.v        Single-cycle baseline
├── Riscv_pipeline.v      5-stage pipelined processor (top module)
├── program.hex           Program loaded by the single-cycle testbench
├── Tb_memory_regfile.v   Testbench: memories + register file
├── Tb_ALU.v              Testbench: ALU
├── tb_control.v          Testbench: control unit
├── tb_hazard_forward.v   Testbench: hazard + forwarding units
├── tb_riscv_single.v     Testbench: single-cycle core
├── tb_riscv_pipeline.v   Testbench: pipelined core
├── tb_benchmark.v        Benchmark: MAC vs standard dot product
├── verif/                Python-driven verification and benchmarks (see below)
│   ├── rvtools.py            Assembler + reference instruction-set simulator
│   ├── tb_prog_runner.v      Runs any hex program on the RTL and dumps state
│   ├── simrun.py             Builds and drives the runner with Verilator
│   ├── directed_tests.py     8 directed regression programs
│   ├── random_diff.py        Differential random testing, RTL vs reference
│   └── bench.py              MAC vs mul+add benchmark suite
├── RISC_V.qpf / .qsf     Quartus project (MAX 10, top = riscv_pipeline)
└── LICENSE
```

## Running Simulations

File names are case-sensitive on Linux and macOS, so use them exactly as listed above.

### Verilator 5 (used to produce the results below)

```bash
SRC="Riscv_pipeline.v pipeline_reg.v Hazard_units.v Forward_units.v \
     Imem.v dmem.v RegFile.v ALU.v control.v"

# Pipeline tests
verilator --binary --timing --top-module tb_riscv_pipeline \
    tb_riscv_pipeline.v $SRC
./obj_dir/Vtb_riscv_pipeline

# Benchmark
verilator --binary --timing --top-module tb_benchmark tb_benchmark.v $SRC
./obj_dir/Vtb_benchmark
```

If the C++ build fails with coroutine errors, add `-CFLAGS "-std=c++20 -fcoroutines"` to the `verilator` command (needed with some GCC setups).

### Icarus Verilog

```bash
iverilog -o tb_pip tb_riscv_pipeline.v Riscv_pipeline.v \
    pipeline_reg.v Hazard_units.v Forward_units.v \
    Imem.v dmem.v RegFile.v ALU.v control.v
vvp tb_pip
```

### ModelSim

```tcl
vlog *.v
vsim tb_riscv_pipeline
run -all
```

> Note: `tb_riscv_single.v` rewrites `program.hex` when it runs. Restore it with `git checkout program.hex` if you do not want that change.

## MAC Instruction Encoding

R-type, custom-0 opcode:

```
[31:25]   [24:20] [19:15] [14:12] [11:7]  [6:0]
funct7    rs2     rs1     funct3  rd      opcode
0000000   B reg   A reg   000     acc     0001011
```

Semantics: `rd = rd + (rs1 × rs2)`

Because `rd` is also a source, a load into `rd` immediately followed by a MAC on the same `rd` needs a 1-cycle stall. The hazard unit handles this.

## Test Results

Checks counted from the PASS lines each testbench prints (simulated with Verilator 5):

| Testbench | Checks | Status |
|---|---|---|
| tb_memory_regfile | 10 | PASS |
| tb_alu | 23 | PASS |
| tb_control | 50 | PASS |
| tb_hazard_forward | 34 | PASS |
| tb_riscv_single | 12 | PASS |
| tb_riscv_pipeline | 21 | PASS |
| tb_benchmark | 2 | PASS |
| **Total** | **152** | **ALL PASS** |

The pipeline testbench covers ALU ops with forwarding, load-use stall, branch taken and not taken, JAL (link value and skipped instruction), chained MACs, and a load feeding a MAC accumulator.

### Differential random testing

`verif/random_diff.py` generates random programs (ALU, immediate and shift ops, `mul`, `mac`, `lw`/`sw`, forward branches, `jal`, `jalr`, `lui`, `auipc`) over a small register set so that data hazards occur constantly, runs each on the RTL pipeline and on the Python reference simulator, and requires the final 32 registers and all 256 data words to match exactly.

| Seeds | Programs | Dynamic instructions | Mismatches |
|---|---|---|---|
| 1 to 4 and 11 to 14 | 4,000 | 487,230 | **0** |

`verif/directed_tests.py` adds 8 directed programs (AUIPC cases, LUI+ADDI, load to MAC accumulator, MAC chain, MUL forwarding), all passing. Run them with:

```bash
export VERILATOR_ROOT=<path to your Verilator install, if needed>
python3 verif/directed_tests.py build_dir
python3 verif/random_diff.py build_dir 500 1      # programs, seed
python3 verif/bench.py build_dir
```

Random testing found a real bug that the hand-written tests missed: see the changelog entry on AUIPC.

### Synthesis estimate (Yosys, generic)

`synth -flatten; abc -lut 4` on `riscv_pipeline`, with the instruction and data memories treated as black boxes (256×32 bits each). This is a technology-independent estimate with Yosys 0.70, **not a Quartus result**.

| Metric | Value |
|---|---|
| Flip-flops | 1,555 (1,024 are the 32×32 register file) |
| 4-input LUTs | 6,148 |
| Longest logic path | 57 LUT levels |

### Place-and-route Fmax (open-source flow, Lattice ECP5)

To get a real timing number without Quartus, the core was synthesised with `yosys synth_ecp5` and placed and routed with `nextpnr-ecp5` (LFE5U-25F, CABGA381, default speed grade) at a 100 MHz target. The instruction memory was taken out as an input port so the datapath is not optimised away; the data memory is real.

| Metric | Value |
|---|---|
| Fmax (best of 3 seeds) | **36.8 MHz** (35.4 to 36.8 MHz across seeds) |
| 4-input LUTs / flip-flops | 1,946 / 573 |
| Hardware multipliers / block RAM | 3 MULT18X18D / 1 DP16KD |

The critical path starts at the data-memory read and runs through the forwarding mux, ALU and the multiply-accumulate. This is a different device family and tool from the MAX 10 / Quartus target, so treat it as an indication of the core's timing, not a MAX 10 result. Pipelining the multiply (or registering the data-memory read) would raise Fmax; that has not been done.

## Known Limitations

- **No Quartus results yet.** The Quartus project points at the correct top module (`riscv_pipeline`), but Fmax and logic-element usage on the MAX 10 have not been measured; only the Yosys estimate above exists. The ECP5 place-and-route result above shows the single-cycle multiply-accumulate path limits clock speed.
- **Not run against the official RISC-V compliance tests.** Verification is by the hand-written testbenches and the differential random tests above.
- Data memory supports word access only (`lw` / `sw`); byte and halfword loads/stores are not implemented.
- Instruction memory is initialised from `program.hex`; programs are assembled with the small Python assembler in `verif/rvtools.py` or by hand, not by a standard toolchain.

## Changelog

- **AUIPC bug fixed.** The ALU's A-operand mux selected the PC based on the opcode of the instruction in the ID stage instead of the one in EX, so `auipc` computed `0 + imm` (and an unrelated instruction after it could get the PC). Found by differential random testing; fixed with an EX-stage flag; covered by `verif/directed_tests.py`.
- Load-use hazard now also covers the MAC accumulator (`rd`). Previously a `lw` immediately followed by a `mac` on the same register accumulated onto the load address instead of the loaded data.
- The MAC accumulator is read through a real register-file port instead of a hierarchical reference (`u_rf.rf[...]`), which worked in simulation but is not synthesizable.
- Quartus project: corrected the top-level entity and removed testbenches from the design file list.
- Test counts in this README corrected to match what the testbenches actually print; branch-not-taken, JAL, and load-to-accumulator tests added.

## Author

**Aditya Dixit**
B.Tech / M.Tech, Electronics & Communication Engineering, VIT Vellore

## References

### Books
- Patterson, D. A., & Hennessy, J. L. (2020). *Computer Organization and Design: RISC-V Edition* (2nd ed.). Morgan Kaufmann.
  Primary reference for the 5-stage pipeline datapath and hazard handling.

- Harris, S., & Harris, D. (2021). *Digital Design and Computer Architecture: RISC-V Edition*. Morgan Kaufmann.
  Reference for Verilog HDL design patterns and control unit structure.

### Specifications
- RISC-V International. (2019). *The RISC-V Instruction Set Manual, Volume I: Unprivileged ISA, Version 20191213*.
  https://riscv.org/technical/specifications/
  Instruction encoding, opcode map, custom opcode space.

- RISC-V International. (2019). *The RISC-V Instruction Set Manual: M Standard Extension for Integer Multiplication and Division*.
  https://riscv.org/technical/specifications/
  MUL/DIV encoding (funct7 = 0000001).

### Papers & Articles
- Hennessy, J. L., & Patterson, D. A. (2019). *A new golden age for computer architecture*. Communications of the ACM, 62(2), 48–60.
  https://doi.org/10.1145/3282307
  Motivation for domain-specific ISA extensions and custom accelerators.

- Jouppi, N. P., et al. (2017). *In-datacenter performance analysis of a tensor processing unit*. Proceedings of ISCA 2017.
  https://doi.org/10.1145/3079856.3080246
  Real-world example of MAC-based domain-specific acceleration (Google TPU).
