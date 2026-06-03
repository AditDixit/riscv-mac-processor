// ============================================================
// alu.v  —  32-bit ALU for RV32I + MAC multiply
//
// alu_ctrl encoding (4 bits):
//   4'b0000  ADD   (add, addi, lw, sw, auipc, jal, jalr)
//   4'b0001  SUB   (sub, beq/bne comparison via subtract)
//   4'b0010  AND   (and, andi)
//   4'b0011  OR    (or, ori)
//   4'b0100  XOR   (xor, xori)
//   4'b0101  SLL   (sll, slli)
//   4'b0110  SRL   (srl, srli)
//   4'b0111  SRA   (sra, srai)
//   4'b1000  SLT   (slt, slti  — signed)
//   4'b1001  SLTU  (sltu, sltiu — unsigned)
//   4'b1010  MUL   (mul — lower 32 bits, used by MAC unit)
//   4'b1011  LUI   (pass src_b directly — lui loads upper imm)
//
// Outputs:
//   result    — 32-bit ALU result
//   zero      — 1 when result == 0  (used by branch logic)
//   negative  — result[31]          (signed comparisons)
//   overflow  — signed overflow flag
// ============================================================
module alu (
    input  wire [31:0] src_a,       // operand A (rs1 or PC)
    input  wire [31:0] src_b,       // operand B (rs2 or immediate)
    input  wire [3:0]  alu_ctrl,    // operation select
    output reg  [31:0] result,      // ALU result
    output wire        zero,        // result == 0
    output wire        negative,    // result[31]
    output wire        overflow     // signed overflow (ADD/SUB)
);

    // Signed interpretations for SLT / SRA / overflow
    wire signed [31:0] signed_a = $signed(src_a);
    wire signed [31:0] signed_b = $signed(src_b);

    // Shift amount is always the lower 5 bits of src_b
    wire [4:0] shamt = src_b[4:0];

    // ---- 33-bit addition for overflow detection ---------------
    // Extend to 33 bits to catch the carry out of bit 31
    wire [32:0] add_ext  = {src_a[31], src_a} + {src_b[31], src_b};
    wire [32:0] sub_ext  = {src_a[31], src_a} - {src_b[31], src_b};

    // Signed overflow:
    //   ADD overflows when both operands have the same sign and
    //       the result has the opposite sign
    //   SUB overflows when operands have different signs and
    //       the result sign differs from src_a
    wire add_overflow = (~src_a[31] & ~src_b[31] &  add_ext[31]) |
                        ( src_a[31] &  src_b[31] & ~add_ext[31]);
    wire sub_overflow = (~src_a[31] &  src_b[31] &  sub_ext[31]) |
                        ( src_a[31] & ~src_b[31] & ~sub_ext[31]);

    // ---- main operation select --------------------------------
    always @(*) begin
        case (alu_ctrl)
            4'b0000: result = src_a + src_b;                       // ADD
            4'b0001: result = src_a - src_b;                       // SUB
            4'b0010: result = src_a & src_b;                       // AND
            4'b0011: result = src_a | src_b;                       // OR
            4'b0100: result = src_a ^ src_b;                       // XOR
            4'b0101: result = src_a << shamt;                      // SLL
            4'b0110: result = src_a >> shamt;                      // SRL (logical)
            4'b0111: result = $signed(src_a) >>> shamt;            // SRA (arithmetic)
            4'b1000: result = (signed_a < signed_b)  ? 32'b1 : 32'b0; // SLT
            4'b1001: result = (src_a    < src_b)     ? 32'b1 : 32'b0; // SLTU
            4'b1010: result = src_a * src_b;                       // MUL (low 32)
            4'b1011: result = src_b;                               // LUI passthrough
            default: result = 32'b0;
        endcase
    end

    // ---- flag outputs ----------------------------------------
    assign zero     = (result == 32'b0);
    assign negative = result[31];
    assign overflow = (alu_ctrl == 4'b0000) ? add_overflow :
                      (alu_ctrl == 4'b0001) ? sub_overflow : 1'b0;

endmodule