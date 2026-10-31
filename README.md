# RISC-V 32-bit Pipelined Processor with MAC Acceleration Unit

5-stage pipelined RISC-V processor in Verilog implementing RV32I (including byte/halfword loads and stores) plus `mul`, and a custom MAC instruction (`rd = rd + rs1 × rs2`) in the custom-0 opcode space. It has load-use hazard detection, branch/jump flushes, EX-EX and MEM-EX forwarding, and an accumulator bypass for back-to-back MACs.

| Headline result | Value |
|---|---|
| MAC speed-up, unrolled 8-element dot product | **1.89×** (17 → 9 cycles) |
| MAC speed-up, loop kernels (dot product, FIR, matrix multiply) | **1.08× to 1.25×** |
| CPI | 1.11 (unrolled dot product) to 1.60 (rolled loop); 1.20 on random hazard-heavy code |
| Directed checks | **175** across 7 testbenches, all passing |
| Differential random testing | **8,000** programs, 974,530 instructions, **0** mismatches |
| RTL coverage | 100% of reachable lines, branches and toggles |
| Fmax (Lattice ECP5, open-source flow) | **37.2 to 38.4 MHz** across 3 seeds |
| Area (ECP5) | 3,077 LUT4, 614 FFs, 3 DSP multipliers, 2 block RAMs |

## ISA coverage

| Group | Instructions |
|---|---|
| ALU (R/I) | add sub and or xor sll srl sra slt sltu, addi andi ori xori slli srli srai slti sltiu |
| Loads / stores | lb lh lw lbu lhu, sb sh sw |
| Control | beq bne blt bge bltu bgeu, jal jalr |
| Upper immediate | lui auipc |
| Memory ordering | fence (no-op, correct for a single in-order hart) |
| M extension | mul only |
| Custom-0 | mac |

`ecall` and `ebreak` decode as no-ops: there are no CSRs or traps. Loads and stores are assumed naturally aligned; a misaligned halfword or word access is not trapped and the low address bits are ignored (the reference simulator models the same behaviour).

## Architecture

```
IF → ID → EX → MEM → WB
          ↑     ↑
   MAC unit    lsu_align (byte lanes, load extension)
```

- **Hazard detection:** 1-cycle load-use stalls (including a load feeding a MAC's accumulator register); taken branches and jumps resolve in EX and flush 2 instructions
- **Forwarding:** EX/MEM → EX and MEM/WB → EX bypass paths, plus an accumulator bypass so chained MACs never stall
- **MAC instruction:** `rd = rd + (rs1 × rs2)`. The register file has a third read port so the MAC can read its own `rd` as the accumulator.
- **Sub-word memory access:** `lsu_align.v` replicates store data into the right byte lanes, generates byte enables for the data memory, and selects and sign/zero-extends loaded bytes and halfwords. It is shared by the pipelined and single-cycle cores.

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

Real kernels load operands and run a loop, and those instructions are the same in both versions, so the whole-program gain is smaller. Each program is assembled from source, run on the RTL pipeline, and cross-checked against the reference instruction-set simulator and an independent Python computation of the answer (all match).

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

Cycles are counted from reset release until the final `jal x0, 0` reaches the EX stage. The MAC saves exactly one instruction (and one cycle) per multiply-accumulate, so the speed-up is bounded by the fraction of the program that is the multiply-add itself. Unrolling raises it, and load-use and branch penalties are paid equally by both versions.

## CPI and hazard statistics (`verif/perf.py`)

The program runner has performance counters for load-use stalls, taken branches and jumps, forwarded operands, and MAC accumulator bypasses. For every program the script checks the identity

```
cycles = instructions + 3 (startup) + load-use stall cycles + 2 × (taken branches + jumps)
```

and it holds exactly for every kernel and all 1,000 random programs, so the counters are validated against the cycle count.

| Program | Instrs | Cycles | CPI | Load-use stalls | Taken branches + jumps | EX/MEM fwds | MEM/WB fwds | MAC acc bypasses |
|---|---|---|---|---|---|---|---|---|
| dot N=64 loop, mul+add | 388 | 581 | 1.497 | 64 | 63 | 128 | 65 | 0 |
| dot N=64 loop, MAC | 324 | 517 | 1.596 | 64 | 63 | 64 | 65 | 0 |
| dot N=64 unrolled, mul+add | 292 | 325 | 1.113 | 0 | 15 | 80 | 49 | 0 |
| dot N=64 unrolled, MAC | 228 | 261 | 1.145 | 0 | 15 | 16 | 1 | 48 |
| FIR 32×16, mul+add | 3778 | 5315 | 1.407 | 512 | 511 | 1568 | 544 | 0 |
| FIR 32×16, MAC | 3266 | 4803 | 1.471 | 512 | 511 | 1056 | 544 | 0 |
| matmul 8×8, mul+add | 4571 | 6108 | 1.336 | 512 | 511 | 1160 | 1088 | 0 |
| matmul 8×8, MAC | 4059 | 5596 | 1.379 | 512 | 511 | 648 | 1088 | 0 |
| 1,000 random programs | 122,553 | 146,915 | **1.199** | 0.018 per instr | 0.078 per instr | 16,242 | 13,215 | 3,425 |

Penalties: a load-use hazard costs 1 cycle and a taken branch or jump costs 2. In the rolled loops, each iteration pays one of each, which is why CPI is about 1.5. Unrolling hides the load latency (zero stalls) and amortises the branch.

The MAC versions have a *higher* CPI but finish sooner: they remove one cheap instruction per multiply-accumulate while the stalls and flushes stay the same. In the unrolled kernel the accumulator bypass feeds every chained MAC directly, so the chain runs without stalls.

## Verification

### Directed testbenches

Checks counted from the PASS lines each testbench prints (simulated with Icarus Verilog 12 and Verilator 5):

| Testbench | Checks | Status |
|---|---|---|
| tb_memory_regfile (memories, byte enables, lsu_align, register file) | 24 | PASS |
| tb_alu | 23 | PASS |
| tb_control | 50 | PASS |
| tb_hazard_forward | 34 | PASS |
| tb_riscv_single | 12 | PASS |
| tb_riscv_pipeline | 30 | PASS |
| tb_benchmark | 2 | PASS |
| **Total** | **175** | **ALL PASS** |

The pipeline testbench covers ALU ops with forwarding, load-use stall, branch taken and not taken, JAL (link value and skipped instruction), chained MACs, a load feeding a MAC accumulator, and byte/halfword loads and stores (sign and zero extension, lane merging, store-to-load, a load-use stall on `lb`) and `fence`.

`verif/directed_tests.py` adds 14 directed programs, all passing, compared against the reference simulator: AUIPC cases, LUI+ADDI, load to MAC accumulator, MAC chain, MUL forwarding, all byte lanes for `lb`/`lbu`, both halves for `lh`/`lhu`, `sb`/`sh` lane merging, `lb` load-use stall, `lbu` into a MAC accumulator, and `fence`. The reference simulator's sub-word results were also checked against hand-computed values.

### Differential random testing

`verif/random_diff.py` generates random programs over a small register set, so data hazards occur constantly. The mix covers ALU, immediate and shift ops, `mul`, `mac`, byte/halfword/word loads and stores, forward branches, `jal`, `jalr`, `lui`, `auipc` and `fence`. Each program runs on the RTL pipeline and on the Python reference simulator, and the final 32 registers and all 256 data words must match exactly.

| Seeds | Programs | Dynamic instructions | Mismatches |
|---|---|---|---|
| 1 to 8 and 11 to 18 (500 each) | 8,000 | 974,530 | **0** |

**Sensitivity check:** planting a bug in `lsu_align.v` makes the same tester fail 55 of 200 programs (`lb` zero-extending) or 165 of 200 (byte enables ignoring the address offset). Random testing also found a real bug the hand-written tests missed; see the changelog entry on AUIPC.

### Code coverage (`verif/coverage.py`)

Verilator line, branch and toggle coverage of the pipeline RTL over 1,034 programs (14 directed, 20 benchmark kernels, 1,000 random):

| Metric | Covered | Notes |
|---|---|---|
| Line | 89 / 92 (96.7%) | The 3 misses are `default:` arms of fully enumerated `case` statements, so they cannot be reached |
| Branch | 36 / 36 (100%) | |
| Toggle | 2,879 / 3,432 (83.9%) | 552 of the 553 misses are PC bits 8 to 31, which cannot change with a 1 KB instruction memory; the last is bit 0 of the JALR target, which the ISA forces to zero |

Excluding those structurally unreachable points, coverage of reachable lines, branches and toggles is 100%.

### Run it

```bash
# Directed testbenches (Icarus), e.g. the pipeline:
iverilog -g2012 -o tb_pip tb_riscv_pipeline.v Riscv_pipeline.v pipeline_reg.v \
    Hazard_units.v Forward_units.v Imem.v dmem.v lsu_align.v RegFile.v ALU.v control.v
vvp tb_pip

# Program-level suite (needs Verilator 5 on PATH, or VERILATOR_ROOT set):
python3 verif/directed_tests.py build_dir
python3 verif/random_diff.py build_dir 500 1      # programs, seed
python3 verif/bench.py build_dir
python3 verif/perf.py build_dir 1000 1            # CPI and hazard statistics
python3 verif/coverage.py cov_dir 1000 1          # line/branch/toggle coverage
```

## Implementation results

### Place and route, Lattice ECP5 (`synth/run_fmax.sh`)

Yosys `synth_ecp5` + nextpnr-ecp5 on an LFE5U-25F (CABGA381), three placement seeds:

| Metric | Value |
|---|---|
| Fmax | **37.2 to 38.4 MHz** (seeds 1/2/3: 38.40, 37.16, 37.23) |
| LUT4 / flip-flops | 3,077 / 614 |
| Distributed RAM (register file) | 48 TRELLIS_RAMW |
| Block RAM / hardware multipliers | 2 DP16KD (instruction and data memory) / 3 MULT18X18D |

**Critical path (≈26 ns: 10.2 ns logic, 15.8 ns routing):** MEM/WB destination register → forwarding-select logic → operand mux → 32×32 multiplier → 32-bit MAC accumulate adder → EX/MEM result → data-memory address. The single-cycle multiplier in EX dominates; pipelining it over two stages is the obvious next step for clock speed.

The FPGA build defines `FPGA_PROG_PORT`, which gives the instruction memory a program-load write port. Without it the empty instruction ROM lets synthesis remove the entire core.

### Intel MAX 10 (Quartus)

`RISC_V.qpf` targets a MAX 10 10M08DAF484C8G, with `FPGA_PROG_PORT` and a 50 MHz constraint (`RISC_V.sdc`) already set. Run compilation and read the logic element count from the Fitter summary and Fmax from TimeQuest's "Fmax Summary".

## File Structure

```
├── Imem.v                Instruction memory (256×32; program.hex in sim, load port on FPGA)
├── dmem.v                Data memory (256×32, byte-enable writes)
├── lsu_align.v           Byte-lane steering: store lanes/byte enables, load extension
├── RegFile.v             32×32 register file (2 read ports + accumulator read port)
├── ALU.v                 ALU: all RV32I ops + MUL
├── control.v             Main decoder + ALU decoder + imm_gen
├── pipeline_reg.v        IF/ID, ID/EX, EX/MEM, MEM/WB registers
├── Hazard_units.v        Stall and flush logic
├── Forward_units.v       EX-EX and MEM-EX forwarding
├── riscv_single.v        Single-cycle baseline
├── Riscv_pipeline.v      5-stage pipelined processor (top module)
├── program.hex           Program loaded by the single-cycle testbench
├── Tb_memory_regfile.v   Testbench: memories, lsu_align, register file
├── Tb_ALU.v              Testbench: ALU
├── tb_control.v          Testbench: control unit
├── tb_hazard_forward.v   Testbench: hazard + forwarding units
├── tb_riscv_single.v     Testbench: single-cycle core
├── tb_riscv_pipeline.v   Testbench: pipelined core
├── tb_benchmark.v        Benchmark: MAC vs standard dot product
├── verif/                Python-driven verification and benchmarks
│   ├── rvtools.py            Assembler + reference instruction-set simulator
│   ├── tb_prog_runner.v      Runs any hex program on the RTL, dumps state and perf counters
│   ├── simrun.py             Builds and drives the runner with Verilator
│   ├── directed_tests.py     14 directed regression programs
│   ├── random_diff.py        Differential random testing, RTL vs reference
│   ├── bench.py              MAC vs mul+add benchmark suite
│   ├── perf.py               CPI and hazard statistics
│   └── coverage.py           Line/branch/toggle coverage
├── synth/run_fmax.sh     Open-source ECP5 synthesis + place and route
├── RISC_V.qpf/.qsf/.sdc  Quartus project (MAX 10, top = riscv_pipeline)
└── LICENSE
```

## MAC Instruction Encoding

R-type, custom-0 opcode:

```
[31:25]   [24:20] [19:15] [14:12] [11:7]  [6:0]
funct7    rs2     rs1     funct3  rd      opcode
0000000   B reg   A reg   000     acc     0001011
```

Semantics: `rd = rd + (rs1 × rs2)`

Because `rd` is also a source, a load into `rd` immediately followed by a MAC on the same `rd` needs a 1-cycle stall. The hazard unit handles this.

## Changelog

- **Byte and halfword memory access.** Added `lb`/`lh`/`lbu`/`lhu`/`sb`/`sh` (previously they silently behaved as `lw`/`sw`) through a shared `lsu_align` module and byte-enable writes in data memory; `fence` documented as a no-op. Extended the reference simulator, random generator, directed programs and pipeline testbench to cover them. Benchmark cycle counts are unchanged.
- **Measurement.** Added performance counters (`perf.py`), code coverage (`coverage.py`) and a reproducible FPGA flow (`synth/run_fmax.sh`, `FPGA_PROG_PORT`).
- **AUIPC fix (found by random testing).** The ALU's A-operand select (PC for AUIPC, rs1 otherwise) was driven from the instruction in ID while the ALU was executing the instruction in EX, so the select applied to the wrong instruction. It is now latched into EX (`ex_auipc`) with the rest of that instruction's controls.

## Author

**Aditya Dixit**
B.Tech, Electronics & Communication Engineering, VIT Vellore

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
