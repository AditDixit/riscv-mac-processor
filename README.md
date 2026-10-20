# RISC-V 32-bit Pipelined Processor with MAC Acceleration Unit

5-stage pipelined RV32I processor in Verilog with a custom MAC instruction (`rd = rd + rs1 × rs2`) in the RISC-V custom-0 opcode space. Includes load-use hazard detection, branch/jump flushes, EX-EX and MEM-EX data forwarding, and a benchmark showing a **1.89× cycle-count speedup** over standard `mul` + `add` for an 8-element dot product.

## Benchmark Result

Dot product of A = [1..8] and B = [8..1] (result 120), simulated cycle counts:

| | Standard (mul + add) | MAC accelerated |
|---|---|---|
| Instructions | 16 | 8 |
| Cycles | 17 | 9 |
| **Speedup** | 1.00× | **1.89×** |

Both versions are checked for the correct result (120) by `tb_benchmark.v`. The speedup is slightly under the ideal 2× because of the 1-cycle pipeline fill that both programs pay.

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

## Known Limitations

- **No synthesis results yet.** The design parses cleanly in Yosys and the Quartus project now points at the correct top module (`riscv_pipeline`), but Fmax and logic-element usage on the MAX 10 have not been measured.
- **Not run against the official RISC-V compliance tests.** Verification is by the hand-written testbenches above.
- Data memory supports word access only (`lw` / `sw`); byte and halfword loads/stores are not implemented.
- Instruction memory is initialised from `program.hex`; programs are hand-assembled rather than produced by a toolchain.

## Changelog

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
