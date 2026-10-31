# RISC-V 32-bit Pipelined Processor with MAC Acceleration Unit

5-stage pipelined RISC-V processor in Verilog implementing RV32I (including byte/halfword loads and stores) plus `mul`, and a custom MAC instruction (`rd = rd + rs1 × rs2`) in the custom-0 opcode space. The multiplier is split across EX and MEM, with the accumulate done in MEM, so the 32×32 multiply is off the critical path and chained MACs still issue back to back.

| Headline result | Value |
|---|---|
| Official RISC-V architecture tests (riscv-arch-test 2.7.4) | **39 / 39** pass: all 38 RV32I tests + `mul-01`, 13,268 signature words matching the Sail reference |
| Fmax (Lattice ECP5, open-source flow) | **49.5 to 50.9 MHz** across 3 seeds (was 37.2 to 38.4 MHz before pipelining the multiplier) |
| Area (ECP5) | 3,159 LUT4, 646 FFs, 3 DSP multipliers, 2 block RAMs |
| MAC speed-up, unrolled 8-element dot product | **1.89×** (17 → 9 cycles) |
| MAC speed-up, loop kernels (dot product, FIR, matrix multiply) | **1.08× to 1.25×** |
| MAC area cost | +319 LUTs (+11%), +34 FFs, no extra DSPs or block RAM, ≈1.5% Fmax |
| CPI | 1.11 (unrolled dot product) to 1.60 (rolled loop); 1.23 on random hazard-heavy code |
| Directed checks | **180** across 7 testbenches, all passing |
| Differential random testing | **8,000** programs, 974,530 instructions, **0** mismatches |
| RTL coverage | 100% of reachable lines, branches and toggles |

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
IF → ID → EX ───────────→ MEM ──────────────→ WB
          │ forwarding    │ lsu_align          │
          │ ALU, branch   │ (byte lanes,       │
          │ mul stage 1:  │  load extension)   │
          │ 3×(16×16)  ──→│ mul stage 2: sum   │
          │ partial prods │ + accumulator ←────┘ WB→MEM accumulator forward
```

- **Two-stage multiplier (`mul_pipe.v`):** EX computes the three 16×16 partial products that affect the low 32 bits and registers them (one ECP5 DSP each); MEM adds them. For a MAC, MEM also adds the accumulator.
- **Accumulator path:** the MAC reads its own `rd` through a third register-file read port in EX. If the instruction just ahead writes that register (a load, MUL, MAC or ALU op), its result is forwarded from WB into the MEM-stage accumulate, so a MAC chain or a load feeding the accumulator never stalls.
- **Hazard detection:** a load or MUL/MAC result is ready at the end of MEM, so an instruction that uses it as `rs1`/`rs2` in the very next slot stalls 1 cycle. Taken branches and jumps resolve in EX and flush 2 instructions.
- **Forwarding:** EX/MEM → EX (registered ALU result) and MEM/WB → EX.
- **Sub-word memory access (`lsu_align.v`):** replicates store data into the right byte lanes, generates byte enables, and selects and sign/zero-extends loaded bytes and halfwords. Shared by the pipelined and single-cycle cores.

### What pipelining the multiplier changed

| | Single-cycle multiplier | Two-stage multiplier |
|---|---|---|
| Fmax (ECP5, 3 seeds) | 37.2 to 38.4 MHz | **49.5 to 50.9 MHz** (+33%) |
| LUT4 / FFs / DSPs | 3,077 / 614 / 3 | 3,159 / 646 / 3 |
| Benchmark kernel cycles (all 20) | baseline | **identical** |
| CPI, 1,000 random programs | 1.199 | 1.231 (+0.034 multiply-use stall cycles per instruction) |
| Load → MAC accumulator | 1-cycle stall | no stall (WB→MEM forward) |

The kernels lose nothing because their multiply results are consumed at least two instructions later (the mul+add baseline is scheduled the way a compiler would for a pipelined multiplier; see below). Random code places results next to their users on purpose, so it pays the occasional stall.

## Benchmark Results

### Straight-line dot product (`tb_benchmark.v`)

Dot product of A = [1..8] and B = [8..1] (result 120), fully unrolled, operands already in registers:

| | Standard (mul + add) | MAC accelerated |
|---|---|---|
| Instructions | 16 | 8 |
| Cycles | 17 | 9 |
| **Speedup** | 1.00× | **1.89×** |

This is the best case: only arithmetic, no loads, no loop control. The standard version alternates two temporaries so no `add` waits on the `mul` right before it.

### Kernels with loads and loops (`verif/bench.py`)

Real kernels load operands and run a loop, and those instructions are the same in both versions, so the whole-program gain is smaller. Each program is assembled from source, run on the RTL pipeline, and cross-checked against the reference instruction-set simulator and an independent Python computation of the answer (all match). The mul+add baseline places an independent instruction (the loop increment) between each `mul` and its `add`, or computes four products into separate registers in the unrolled kernels, so it never pays a multiply-use stall.

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

Cycles are counted from reset release until the final `jal x0, 0` reaches the EX stage. The MAC saves exactly one instruction (and one cycle) per multiply-accumulate, so the speed-up is bounded by the fraction of the program that is the multiply-add itself. Unrolling raises it; load-use and branch penalties are paid equally by both versions.

### Cost of the MAC extension

Building with `NO_MAC_EXT` removes the custom instruction (the core keeps `mul`):

| ECP5 | Without MAC | With MAC | Cost |
|---|---|---|---|
| LUT4 | 2,840 | 3,159 | **+319 (+11.2%)** |
| Flip-flops | 612 | 646 | +34 (accumulator pipeline register) |
| Distributed RAM (TRELLIS_RAMW) | 32 | 48 | +16 (the register file's third read port) |
| DSP multipliers / block RAM | 3 / 2 | 3 / 2 | none |
| Fmax, mean of 3 seeds | 50.9 MHz | 50.1 MHz | ≈1.5%, within seed-to-seed spread |

## CPI and hazard statistics (`verif/perf.py`)

The program runner has performance counters for load-use stalls, multiply-use stalls, taken branches and jumps, forwarded operands and MAC accumulator forwards. For every program the script checks the identity

```
cycles = instructions + 3 (startup) + load-use stalls + multiply-use stalls + 2 × (taken branches + jumps)
```

and it holds exactly for every kernel and all 1,000 random programs, so the counters are validated against the cycle count.

| Program | Instrs | Cycles | CPI | Load-use stalls | Mul-use stalls | Taken branches + jumps | EX/MEM fwds | MEM/WB fwds | MAC acc fwds (WB→MEM) |
|---|---|---|---|---|---|---|---|---|---|
| dot N=64 loop, mul+add | 388 | 581 | 1.497 | 64 | 0 | 63 | 0 | 194 | 0 |
| dot N=64 loop, MAC | 324 | 517 | 1.596 | 64 | 0 | 63 | 64 | 65 | 0 |
| dot N=64 unrolled, mul+add | 292 | 325 | 1.113 | 0 | 0 | 15 | 64 | 1 | 0 |
| dot N=64 unrolled, MAC | 228 | 261 | 1.145 | 0 | 0 | 15 | 16 | 1 | 48 |
| FIR 32×16, mul+add | 3778 | 5315 | 1.407 | 512 | 0 | 511 | 544 | 1600 | 0 |
| FIR 32×16, MAC | 3266 | 4803 | 1.471 | 512 | 0 | 511 | 1056 | 544 | 0 |
| matmul 8×8, mul+add | 4571 | 6108 | 1.336 | 512 | 0 | 511 | 648 | 1088 | 0 |
| matmul 8×8, MAC | 4059 | 5596 | 1.379 | 512 | 0 | 511 | 648 | 1088 | 0 |
| 1,000 random programs | 122,553 | 150,846 | **1.231** | 0.016 / instr | 0.034 / instr | 0.078 / instr | 12,277 | 16,402 | 1,719 |

Penalties: a load-use or multiply-use hazard costs 1 cycle and a taken branch or jump costs 2. In the rolled loops each iteration pays one load-use stall and one branch flush, which is why CPI is about 1.5. Unrolling hides the load latency (zero stalls) and amortises the branch.

The MAC versions have a *higher* CPI but finish sooner: they remove one cheap instruction per multiply-accumulate while the stalls and flushes stay the same. In the unrolled kernel every chained MAC takes its accumulator from the WB→MEM forward, so the chain runs without stalls.

## Verification

### Official RISC-V architecture tests (`verif/arch/run_arch.py`)

The script fetches [riscv-arch-test](https://github.com/riscv-non-isa/riscv-arch-test) release 2.7.4 (the last release that ships reference signatures, generated by the Sail formal model of the ISA), builds each test with the RISC-V GCC toolchain, runs it on the pipeline in Verilator, and compares the signature region word for word with the reference.

| Suite | Tests | Result |
|---|---|---|
| RV32I (all ALU, shift, compare, branch, jump, load/store alignment, lui/auipc, fence) | 38 | **38 pass** |
| M: `mul-01` | 1 | **1 pass** |
| **Total** | **39** | **39 / 39, 13,268 signature words, 0 mismatches** |

The rest of the M suite (`mulh*`, `div*`, `rem*`) is not run because those instructions are not implemented. The tests need no traps or CSRs. Two build details: the image is linked at address 0 and loaded into both instruction and data memory, and `jalr-01` contains `la x0, <label>`, which newer assemblers reject; since writing `x0` has no effect it is replaced by two `nop`s of the same size. **Sensitivity check:** planting a sign-extension bug in `lb` makes exactly one test, `lb-align-01`, fail (32 of 36 words).

### Directed testbenches

Checks counted from the PASS lines each testbench prints (simulated with Icarus Verilog 12 and Verilator 5):

| Testbench | Checks | Status |
|---|---|---|
| tb_memory_regfile (memories, byte enables, lsu_align, register file) | 24 | PASS |
| tb_alu | 23 | PASS |
| tb_control | 50 | PASS |
| tb_hazard_forward (load-use, multiply-use, flush priority, forwarding) | 39 | PASS |
| tb_riscv_single | 12 | PASS |
| tb_riscv_pipeline | 30 | PASS |
| tb_benchmark | 2 | PASS |
| **Total** | **180** | **ALL PASS** |

The pipeline testbench covers ALU ops with forwarding, load-use stall, branch taken and not taken, JAL (link value and skipped instruction), chained MACs, a load feeding a MAC accumulator, byte/halfword loads and stores (sign and zero extension, lane merging, store-to-load, a load-use stall on `lb`) and `fence`.

`verif/directed_tests.py` adds 14 directed programs compared against the reference simulator: AUIPC cases, LUI+ADDI, load to MAC accumulator, MAC chain, MUL forwarding, all byte lanes for `lb`/`lbu`, both halves for `lh`/`lhu`, `sb`/`sh` lane merging, `lb` load-use stall, `lbu` into a MAC accumulator, and `fence`.

### Differential random testing

`verif/random_diff.py` generates random programs over a small register set, so data hazards (including MUL/MAC results used immediately) occur constantly. The mix covers ALU, immediate and shift ops, `mul`, `mac`, byte/halfword/word loads and stores, forward branches, `jal`, `jalr`, `lui`, `auipc` and `fence`. Each program runs on the RTL pipeline and on the Python reference simulator, and the final 32 registers and all 256 data words must match exactly.

| Seeds | Programs | Dynamic instructions | Mismatches |
|---|---|---|---|
| 1 to 8 and 11 to 18 (500 each) | 8,000 | 974,530 | **0** |

**Sensitivity check:** planting a bug in `lsu_align.v` makes the same tester fail 55 of 200 programs (`lb` zero-extending) or 165 of 200 (byte enables ignoring the address offset). Random testing also found a real bug the hand-written tests missed; see the changelog entry on AUIPC.

### Code coverage (`verif/coverage.py`)

Verilator line, branch and toggle coverage of the pipeline RTL over 1,034 programs (14 directed, 20 benchmark kernels, 1,000 random):

| Metric | Covered | Notes |
|---|---|---|
| Line | 91 / 94 (96.8%) | The 3 misses are `default:` arms of fully enumerated `case` statements, so they cannot be reached |
| Branch | 38 / 38 (100%) | |
| Toggle | 3,165 / 3,718 (85.1%) | 552 of the 553 misses are PC bits 8 to 31, which cannot change with a 1 KB instruction memory; the last is bit 0 of the JALR target, which the ISA forces to zero |

Excluding those structurally unreachable points, coverage of reachable lines, branches and toggles is 100%. Code coverage shows what the tests exercised; the checking comes from the reference comparisons above.

### Run it

```bash
# Directed testbenches (Icarus), e.g. the pipeline:
iverilog -g2012 -o tb_pip tb_riscv_pipeline.v Riscv_pipeline.v pipeline_reg.v \
    Hazard_units.v Forward_units.v Imem.v dmem.v lsu_align.v mul_pipe.v \
    RegFile.v ALU.v control.v
vvp tb_pip

# Program-level suite (needs Verilator 5 on PATH, or VERILATOR_ROOT set):
python3 verif/directed_tests.py build_dir
python3 verif/random_diff.py build_dir 500 1      # programs, seed
python3 verif/bench.py build_dir
python3 verif/perf.py build_dir 1000 1            # CPI and hazard statistics
python3 verif/coverage.py cov_dir 1000 1          # line/branch/toggle coverage

# Official architecture tests (also needs git and riscv64-unknown-elf-gcc):
python3 verif/arch/run_arch.py arch_dir

# FPGA implementation (needs Yosys and nextpnr-ecp5):
synth/run_fmax.sh                                 # with MAC
EXTRA_DEFINES=-DNO_MAC_EXT synth/run_fmax.sh synth/build_nomac   # without
```

### Running everything in Quartus Prime and Questa (Intel MAX 10)

The same checks run in the Intel toolchain with no Verilator or RISC-V compiler, only Python 3 and Questa (the simulator installed with Quartus Prime):

```bash
python verif/questa/gen_vectors.py verif/questa/vectors   # pure Python, ~10 s
python verif/questa/run_questa.py all                     # Questa: 180 checks, 14 directed,
                                                          # 20 benchmarks, 8,000 random, 39 arch tests
```

`run_questa.py` simulates the `FPGA_SYNC_MEM` memories (`imem_sync.v`, `dmem_sync.v`), the exact RTL that the Quartus build synthesises. These keep a registered read address, as MAX 10 M9K block RAM requires, and are cycle-for-cycle identical to `imem.v` / `dmem.v` (every suite gives the same results with either). The official architecture tests run from prebuilt images in `verif/questa/arch` (made by `verif/questa/export_arch.py`).

For implementation, open `RISC_V.qpf` and compile: the project sets `FPGA_PROG_PORT`, `FPGA_SYNC_MEM` and a 50 MHz constraint. Uncomment `NO_MAC_EXT` in `RISC_V.qsf` to measure the MAC's cost. The `baseline-single-cycle-mul` branch is the design before the multiplier was pipelined, with the same memories, for a like-for-like before/after comparison.

## Implementation results

### Place and route, Lattice ECP5 (`synth/run_fmax.sh`)

Yosys `synth_ecp5` + nextpnr-ecp5 on an LFE5U-25F (CABGA381), three placement seeds:

| Metric | Value |
|---|---|
| Fmax | **49.5 to 50.9 MHz** (seeds 1/2/3: 49.53, 50.88, 50.01) |
| LUT4 / flip-flops | 3,159 / 646 |
| Distributed RAM (register file, 3 read ports) | 48 TRELLIS_RAMW |
| Block RAM / hardware multipliers | 2 DP16KD (instruction and data memory) / 3 MULT18X18D |

**Critical path (≈19.6 ns: 7.1 ns logic, 12.5 ns routing):** EX/MEM destination register → forwarding compare → forwarded operand → 32-bit branch comparator → taken/flush logic → next-PC mux → instruction-memory address. This is the usual limit for a 5-stage core that resolves branches in EX. Before the multiplier was pipelined, the path ran through the 32×32 multiplier and the MAC adder instead (≈26 ns).

The FPGA build defines `FPGA_PROG_PORT`, which gives the instruction memory a program-load write port. Without it the empty instruction ROM lets synthesis remove the entire core.

### Intel MAX 10 (Quartus)

`RISC_V.qpf` targets a MAX 10 10M08DAF484C8G, with `FPGA_PROG_PORT` and a 50 MHz constraint (`RISC_V.sdc`) already set. Run compilation and read the logic element count from the Fitter summary and Fmax from TimeQuest's "Fmax Summary".

## File Structure

```
├── Imem.v                Instruction memory (2^AW words; program.hex in sim, load port on FPGA)
├── dmem.v                Data memory (2^AW words, byte-enable writes)
├── lsu_align.v           Byte-lane steering: store lanes/byte enables, load extension
├── mul_pipe.v            Two-stage multiplier (16×16 partial products in EX, sum in MEM)
├── imem_sync.v / dmem_sync.v  Block-RAM memories for MAX 10 (FPGA_SYNC_MEM), cycle-identical
├── RegFile.v             32×32 register file (2 read ports + accumulator read port)
├── ALU.v                 ALU: all RV32I ops (+ single-cycle MUL for the single-cycle core)
├── control.v             Main decoder + ALU decoder + imm_gen
├── pipeline_reg.v        IF/ID, ID/EX, EX/MEM, MEM/WB registers
├── Hazard_units.v        Load-use / multiply-use stalls, branch flushes
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
│   ├── coverage.py           Line/branch/toggle coverage
│   ├── arch/                 Official riscv-arch-test runner (target macros, link script, testbench)
│   └── questa/               Questa/ModelSim flow: batch testbench, vector generator, prebuilt arch tests
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

Semantics: `rd = rd + (rs1 × rs2)`, low 32 bits (the accumulator wraps modulo 2^32; there is no saturation or wider accumulator).

## Changelog

- **Two-stage multiplier.** The 32×32 multiply was split into registered 16×16 partial products (EX) and a final sum plus accumulate (MEM), with a WB→MEM accumulator forward and a 1-cycle multiply-use stall. Fmax rose from 37.2–38.4 MHz to 49.5–50.9 MHz; benchmark cycle counts are unchanged, and the load → MAC-accumulator stall is gone.
- **Official architecture tests.** Added a riscv-arch-test 2.7.4 runner; all 38 RV32I tests and `mul-01` pass against the Sail reference signatures. Memories got a size parameter (default unchanged at 1 KB) so the larger test images fit.
- **MAC cost measurement.** `NO_MAC_EXT` builds the core without the custom instruction for an area/Fmax comparison.
- **Byte and halfword memory access.** Added `lb`/`lh`/`lbu`/`lhu`/`sb`/`sh` (previously they silently behaved as `lw`/`sw`) through a shared `lsu_align` module and byte-enable writes in data memory; `fence` documented as a no-op. Extended the reference simulator, random generator, directed programs and pipeline testbench to cover them.
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

- RISC-V International. *riscv-arch-test*, release 2.7.4.
  https://github.com/riscv-non-isa/riscv-arch-test
  Architectural tests and Sail reference signatures used for compliance checking.

### Papers & Articles
- Hennessy, J. L., & Patterson, D. A. (2019). *A new golden age for computer architecture*. Communications of the ACM, 62(2), 48–60.
  https://doi.org/10.1145/3282307
  Motivation for domain-specific ISA extensions and custom accelerators.

- Jouppi, N. P., et al. (2017). *In-datacenter performance analysis of a tensor processing unit*. Proceedings of ISCA 2017.
  https://doi.org/10.1145/3079856.3080246
  Real-world example of MAC-based domain-specific acceleration (Google TPU).
