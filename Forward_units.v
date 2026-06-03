// ============================================================
// forward_unit.v  —  Data Forwarding Unit
//
// Resolves RAW (Read After Write) data hazards by forwarding
// results from later pipeline stages back to the EX stage muxes.
//
// Two forwarding paths:
//
//   EX-EX:  Result produced by previous instruction (now in MEM)
//           forwarded to current instruction's ALU input.
//           Source: ex_mem_rd / ex_mem_reg_write
//
//   MEM-EX: Result produced two instructions ago (now in WB)
//           forwarded to current instruction's ALU input.
//           Source: mem_wb_rd / mem_wb_reg_write
//
// forward_a / forward_b encoding:
//   2'b00  — no forwarding, use register file value (rd1/rd2)
//   2'b10  — EX-EX forward:  use ex_mem stage result
//   2'b01  — MEM-EX forward: use mem_wb stage result
//
// Priority: EX-EX takes priority over MEM-EX when both match
// (the more recent value is always correct).
//
// x0 is never forwarded (it's hardwired zero; writing x0 is a NOP).
// ============================================================
module forward_unit (
    // Register addresses of the instruction currently in EX
    input  wire [4:0]  id_ex_rs1,
    input  wire [4:0]  id_ex_rs2,

    // EX/MEM pipeline register (instruction just finished EX)
    input  wire [4:0]  ex_mem_rd,
    input  wire        ex_mem_reg_write,

    // MEM/WB pipeline register (instruction just finished MEM)
    input  wire [4:0]  mem_wb_rd,
    input  wire        mem_wb_reg_write,

    // Forwarding select outputs
    output reg  [1:0]  forward_a,    // mux select for ALU src_a
    output reg  [1:0]  forward_b     // mux select for ALU src_b
);

    always @(*) begin
        // ── Forward A (rs1) ───────────────────────────────
        if (ex_mem_reg_write &&
            ex_mem_rd != 5'b0 &&
            ex_mem_rd == id_ex_rs1)
            forward_a = 2'b10;   // EX-EX forward

        else if (mem_wb_reg_write &&
                 mem_wb_rd != 5'b0 &&
                 mem_wb_rd == id_ex_rs1)
            forward_a = 2'b01;   // MEM-EX forward

        else
            forward_a = 2'b00;   // no forward, use reg file

        // ── Forward B (rs2) ───────────────────────────────
        if (ex_mem_reg_write &&
            ex_mem_rd != 5'b0 &&
            ex_mem_rd == id_ex_rs2)
            forward_b = 2'b10;   // EX-EX forward

        else if (mem_wb_reg_write &&
                 mem_wb_rd != 5'b0 &&
                 mem_wb_rd == id_ex_rs2)
            forward_b = 2'b01;   // MEM-EX forward

        else
            forward_b = 2'b00;   // no forward, use reg file
    end

endmodule