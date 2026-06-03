// ============================================================
// hazard_unit.v  —  Hazard Detection Unit
//
// Detects two classes of hazard and takes corrective action:
//
// 1. LOAD-USE HAZARD (data hazard, cannot be forwarded)
//    When a LW is in EX and the very next instruction needs
//    that register, we must stall for 1 cycle:
//      - Freeze PC and IF/ID register (stall = 1)
//      - Flush ID/EX register (insert NOP bubble)
//    Condition:
//      id_ex_mem_read &&
//      (id_ex_rd == if_id_rs1 || id_ex_rd == if_id_rs2)
//
// 2. CONTROL HAZARD (branch / jump taken)
//    When a branch is resolved in EX or a jump is decoded in ID,
//    the wrong instructions are already in IF and ID.
//    We flush them (replace with NOPs):
//      - flush_if_id  = 1  (kill instruction in ID)
//      - flush_id_ex  = 1  (kill instruction in EX)
//    Branch condition evaluated in EX stage.
//    JAL/JALR resolved in EX stage as well.
//
// Note: EX-EX and MEM-EX data hazards are handled by the
//       forwarding unit — no stall needed for those.
// ============================================================
module hazard_unit (
    // Load-use hazard inputs
    input  wire        id_ex_mem_read,   // LW is in EX stage
    input  wire [4:0]  id_ex_rd,         // destination of LW in EX
    input  wire [4:0]  if_id_rs1,        // rs1 of instruction in ID
    input  wire [4:0]  if_id_rs2,        // rs2 of instruction in ID

    // Control hazard inputs
    input  wire        branch_taken,     // branch resolved as taken (from EX)
    input  wire        jump,             // JAL/JALR in EX stage

    // Outputs
    output reg         stall,            // 1 = freeze PC + IF/ID
    output reg         flush_if_id,      // 1 = flush IF/ID  (insert NOP in ID)
    output reg         flush_id_ex       // 1 = flush ID/EX  (insert NOP in EX)
);

    always @(*) begin
        // Defaults
        stall        = 1'b0;
        flush_if_id  = 1'b0;
        flush_id_ex  = 1'b0;

        // ── Load-use stall ────────────────────────────────
        if (id_ex_mem_read &&
            ((id_ex_rd == if_id_rs1 && if_id_rs1 != 5'b0) ||
             (id_ex_rd == if_id_rs2 && if_id_rs2 != 5'b0))) begin
            stall       = 1'b1;   // freeze PC and IF/ID
            flush_id_ex = 1'b1;   // insert bubble into EX
        end

        // ── Control hazard flush ──────────────────────────
        // Flush takes priority to kill wrong-path instructions.
        // Stall + flush can't happen simultaneously because a
        // branch/jump can't be in EX while a load-use stall fires
        // (the stall would have delayed the branch by 1 cycle).
        if (branch_taken || jump) begin
            flush_if_id = 1'b1;   // kill instruction now in ID
            flush_id_ex = 1'b1;   // kill instruction now in EX
            stall       = 1'b0;   // never stall during flush
        end
    end

endmodule