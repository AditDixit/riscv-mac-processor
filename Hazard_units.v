// ============================================================
// hazard_unit.v  —  Hazard Detection Unit
//
// Detects two classes of hazard and takes corrective action:
//
// 1. LOAD-USE and MULTIPLY-USE HAZARDS (cannot be forwarded in time)
//    A load's data and a MUL/MAC's result are both produced at the
//    end of MEM (the multiplier is split across EX and MEM, see
//    mul_pipe.v). If the very next instruction reads that register
//    as rs1 or rs2, it must wait 1 cycle:
//      - Freeze PC and IF/ID register (stall = 1)
//      - Flush ID/EX register (insert NOP bubble)
//    After the bubble the value is forwarded from MEM/WB.
//    Condition:
//      (id_ex_mem_read || id_ex_mul) &&
//      (id_ex_rd == if_id_rs1 || id_ex_rd == if_id_rs2)
//
//    A MAC's *accumulator* (its rd) needs no stall here: the
//    accumulate add happens in MEM, and the pipeline forwards the
//    previous instruction's result from WB into MEM. That covers a
//    load, a MUL, or another MAC writing the accumulator just before.
//
// 2. CONTROL HAZARD (branch / jump taken)
//    Branches and JAL/JALR resolve in EX. The two younger
//    instructions in IF and ID are on the wrong path:
//      - flush_if_id  = 1  (kill instruction in ID)
//      - flush_id_ex  = 1  (kill instruction in EX)
//
// Note: all other data hazards are handled by the forwarding unit.
// ============================================================
module hazard_unit (
    // Data hazard inputs
    input  wire        id_ex_mem_read,   // load in EX stage
    input  wire        id_ex_mul,        // MUL or MAC in EX stage
    input  wire [4:0]  id_ex_rd,         // destination of the EX instruction
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

        // ── Load-use / multiply-use stall ─────────────────
        if ((id_ex_mem_read || id_ex_mul) &&
            ((id_ex_rd == if_id_rs1 && if_id_rs1 != 5'b0) ||
             (id_ex_rd == if_id_rs2 && if_id_rs2 != 5'b0))) begin
            stall       = 1'b1;   // freeze PC and IF/ID
            flush_id_ex = 1'b1;   // insert bubble into EX
        end

        // ── Control hazard flush ──────────────────────────
        // Flush takes priority to kill wrong-path instructions.
        if (branch_taken || jump) begin
            flush_if_id = 1'b1;   // kill instruction now in ID
            flush_id_ex = 1'b1;   // kill instruction now in EX
            stall       = 1'b0;   // never stall during flush
        end
    end

endmodule
