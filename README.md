# riscv-mac-processor
5-stage pipelined RISC-V (RV32I) processor in Verilog with a custom MAC instruction (rd = rd + rs1×rs2) using the RISC-V custom-0 opcode space. Includes full hazard detection, EX-EX/MEM-EX data forwarding, and a benchmark showing 1.89× speedup over standard mul+add for dot-product computation.
