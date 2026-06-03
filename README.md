# riscv-mac-processor
5-stage pipelined RISC-V (RV32I) processor in Verilog with a custom MAC instruction (rd = rd + rs1×rs2) using the RISC-V custom-0 opcode space. Includes full hazard detection, EX-EX/MEM-EX data forwarding, and a benchmark showing 1.89× speedup over standard mul+add for dot-product computation.

# RISC-V 32-bit Pipelined Processor with MAC Acceleration Unit

A fully verified 5-stage pipelined RV32I processor implemented in Verilog HDL,
extended with a custom MAC (Multiply-Accumulate) instruction for AI/DSP workloads.

## Benchmark Result

| | Standard (mul+add) | MAC Accelerated |
|---|---|---|
| Instructions | 16 | 8 |
| Cycles | 17 | 9 |
| **Speedup** | 1.00× | **1.89×** |

## Architecture

```
IF → ID → EX → MEM → WB
          ↑
    MAC Unit (custom-0 opcode)
```

- **Hazard Detection**: Load-use stalls, branch/jump flushes
- **Data Forwarding**: EX-EX and MEM-EX bypass paths
- **MAC Instruction**: `rd = rd + (rs1 × rs2)` — RISC-V custom-0 opcode space

## File Structure

```
├── imem.v              Instruction memory (256×32)
├── dmem.v              Data memory (256×32)
├── regfile.v           32×32 register file
├── alu.v               ALU — all RV32I ops + MUL
├── control.v           Main decoder + ALU decoder + imm_gen
├── pipeline_regs.v     IF/ID, ID/EX, EX/MEM, MEM/WB latches
├── hazard_unit.v       Stall and flush logic
├── forward_unit.v      EX-EX and MEM-EX forwarding
├── riscv_single.v      Single-cycle baseline
├── riscv_pipeline.v    5-stage pipelined processor (top module)
├── tb_memory_regfile.v Testbench: memories + register file
├── tb_alu.v            Testbench: ALU (25 cases)
├── tb_control.v        Testbench: control unit (50 cases)
├── tb_hazard_forward.v Testbench: hazard + forwarding (32 cases)
├── tb_riscv_single.v   Testbench: single-cycle (12 cases)
├── tb_riscv_pipeline.v Testbench: pipeline (14 cases)
├── tb_benchmark.v      Benchmark: MAC vs standard dot product
└── RISC_V_Report.docx  Full project report
```

## Running Simulations

### Icarus Verilog (command line)

```bash
# Run all pipeline tests
iverilog -o tb_pip tb_riscv_pipeline.v riscv_pipeline.v \
    pipeline_regs.v hazard_unit.v forward_unit.v \
    imem.v dmem.v regfile.v alu.v control.v
vvp tb_pip

# Run benchmark
iverilog -o tb_bench tb_benchmark.v riscv_pipeline.v \
    pipeline_regs.v hazard_unit.v forward_unit.v \
    imem.v dmem.v regfile.v alu.v control.v
vvp tb_bench
```

### ModelSim

```tcl
vlog *.v
vsim tb_riscv_pipeline
run -all
```

## MAC Instruction Encoding

R-type, custom-0 opcode:

```
[31:25]   [24:20] [19:15] [14:12] [11:7]  [6:0]
funct7    rs2     rs1     funct3  rd      opcode
0000000   B reg   A reg   000     acc     0001011
```

Semantics: `rd = rd + (rs1 × rs2)`

## Test Results

| Testbench | Cases | Status |
|---|---|---|
| tb_memory_regfile | 7 | PASS |
| tb_alu | 25 | PASS |
| tb_control | 50 | PASS |
| tb_hazard_forward | 32 | PASS |
| tb_riscv_single | 12 | PASS |
| tb_riscv_pipeline | 14 | PASS |
| tb_benchmark | 2 | PASS |


---

## Author

**Aditya Dixit**
B.Tech / M.Tech — Electronics & Communication 
*Department of electronics and communication, Vit Vellore*


---

## References

### Books
- Patterson, D. A., & Hennessy, J. L. (2020). *Computer Organization and Design:
  RISC-V Edition* (2nd ed.). Morgan Kaufmann.
  — Primary reference for the 5-stage pipeline datapath and hazard handling.

- Harris, S., & Harris, D. (2021). *Digital Design and Computer Architecture:
  RISC-V Edition*. Morgan Kaufmann.
  — Reference for Verilog HDL design patterns and control unit structure.

### Specifications
- RISC-V International. (2019). *The RISC-V Instruction Set Manual, Volume I:
  Unprivileged ISA, Version 20191213*.
  https://riscv.org/technical/specifications/
  — Official ISA specification: instruction encoding, opcode map, custom opcode space.

- RISC-V International. (2019). *The RISC-V Instruction Set Manual — M Standard
  Extension for Integer Multiplication and Division*.
  https://riscv.org/technical/specifications/
  — Reference for MUL/DIV encoding (funct7 = 0000001).

### Papers & Articles
- Hennessy, J. L., & Patterson, D. A. (2019). *A new golden age for computer
  architecture*. Communications of the ACM, 62(2), 48–60.
  https://doi.org/10.1145/3282307
  — Motivation for domain-specific ISA extensions and custom accelerators.

- Jouppi, N. P., et al. (2017). *In-datacenter performance analysis of a tensor
  processing unit*. Proceedings of ISCA 2017.
  https://doi.org/10.1145/3079856.3080246
  — Real-world example of MAC-based domain-specific acceleration (Google TPU).


| **Total** | **142** | **ALL PASS** |

