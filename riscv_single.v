// ============================================================
// riscv_single.v  —  Single-Cycle RV32I + MAC Processor
//
// Datapath summary:
//   PC  →  IMEM  →  Decode  →  RegFile read
//       →  ImmGen + Control
//       →  ALU   →  DMEM (optional)
//       →  WB mux  →  RegFile write
//
// Branch/Jump target calculation:
//   Branch  : PC + imm  (B-type offset)
//   JAL     : PC + imm  (J-type offset)
//   JALR    : rs1 + imm (I-type, LSB forced to 0)
//
// MAC instruction (custom-0, opcode 0001011):
//   rd = rd_prev + (rs1 * rs2)
//   The accumulator is rd itself — we read rd as a third
//   register port and feed it into the MAC adder.
// ============================================================
module riscv_single (
    input  wire        clk,
    input  wire        rst,        // synchronous active-high reset
    output wire [31:0] pc_out      // current PC (for testbench inspection)
);

    // ── PC ────────────────────────────────────────────────────
    reg  [31:0] pc;
    wire [31:0] pc_plus4    = pc + 32'd4;
    wire [31:0] pc_branch;          // PC + imm
    wire [31:0] pc_jalr;            // rs1 + imm, LSB cleared
    wire [31:0] pc_next;

    assign pc_out = pc;

    // ── Instruction fetch ─────────────────────────────────────
    wire [31:0] instr;
    imem u_imem (.addr(pc), .instr(instr));

    // ── Instruction fields ────────────────────────────────────
    wire [6:0] opcode  = instr[6:0];
    wire [4:0] rs1     = instr[19:15];
    wire [4:0] rs2     = instr[24:20];
    wire [4:0] rd      = instr[11:7];
    wire [2:0] funct3  = instr[14:12];
    wire       funct7_5 = instr[30];

    // ── Control signals ───────────────────────────────────────
    wire        reg_write, alu_src, mem_write, mem_read;
    wire        mem_to_reg, branch, jump, jalr_sig, lui_op, mac_op;
    wire [1:0]  alu_op;
    wire [3:0]  alu_ctrl;

    main_decoder u_main_dec (
        .opcode(opcode),
        .reg_write(reg_write), .alu_src(alu_src),
        .mem_write(mem_write), .mem_read(mem_read),
        .mem_to_reg(mem_to_reg), .branch(branch),
        .jump(jump), .jalr(jalr_sig), .lui_op(lui_op),
        .mac_op(mac_op), .alu_op(alu_op)
    );

    alu_decoder u_alu_dec (
        .alu_op(alu_op), .funct3(funct3),
        .funct7_5(funct7_5), .opcode_5(opcode[5]),
        .lui_op(lui_op), .alu_ctrl(alu_ctrl)
    );

    // ── Immediate generator ───────────────────────────────────
    wire [31:0] imm_ext;
    imm_gen u_imm (.instr(instr), .imm_ext(imm_ext));

    // ── Register file ─────────────────────────────────────────
    wire [31:0] rf_rd1, rf_rd2, rf_rd_acc;
    wire [31:0] result_wb;         // write-back data (defined below)

    regfile u_rf (
        .clk(clk), .we3(reg_write),
        .ra1(rs1), .ra2(rs2), .wa3(rd),
        .wd3(result_wb), .rd1(rf_rd1), .rd2(rf_rd2)
    );

    // Third read port for MAC accumulator (reads destination register rd)
    // Direct combinational read from the register file array.
    // Write-through: if WB is writing to rd this same cycle, forward
    // the new value so back-to-back MAC instructions accumulate correctly.
    // Read current accumulator value directly from register file.
    // In single-cycle, the previous instruction's write has already
    // settled before this instruction's combinational path runs.
    // x0 is always zero per the ISA.
    wire [31:0] acc_val;
    assign acc_val = (rd == 5'b0) ? 32'b0 : u_rf.rf[rd];

    // ── ALU ───────────────────────────────────────────────────
    wire [31:0] alu_src_a;
    wire [31:0] alu_src_b;
    wire [31:0] alu_result;
    wire        alu_zero, alu_neg, alu_ovf;

    // src_a: for AUIPC use PC; otherwise rs1
    assign alu_src_a = (opcode == 7'b0010111) ? pc : rf_rd1;

    // src_b: immediate or rs2
    assign alu_src_b = alu_src ? imm_ext : rf_rd2;

    alu u_alu (
        .src_a(alu_src_a), .src_b(alu_src_b),
        .alu_ctrl(alu_ctrl),
        .result(alu_result),
        .zero(alu_zero), .negative(alu_neg), .overflow(alu_ovf)
    );

    // ── MAC adder ─────────────────────────────────────────────
    // result = acc + (rs1 * rs2)
    // alu_result already holds rs1*rs2 when mac_op=1 (alu_ctrl=MUL)
    wire [31:0] mac_result = acc_val + alu_result;

    // ── Data memory ───────────────────────────────────────────
    wire [31:0] dmem_rd;
    dmem u_dmem (
        .clk(clk), .we(mem_write),
        .addr(alu_result), .wd(rf_rd2),
        .rd(dmem_rd)
    );

    // ── Branch logic ─────────────────────────────────────────
    // Evaluate branch condition from funct3
    reg branch_taken;
    always @(*) begin
        case (funct3)
            3'b000: branch_taken = alu_zero;                    // BEQ
            3'b001: branch_taken = ~alu_zero;                   // BNE
            3'b100: branch_taken = alu_neg ^ alu_ovf;          // BLT  (signed)
            3'b101: branch_taken = ~(alu_neg ^ alu_ovf);       // BGE  (signed)
            3'b110: branch_taken = ~alu_zero & ~alu_result[31]; // BLTU (unsigned)
            3'b111: branch_taken = alu_zero | ~alu_result[31];  // BGEU (unsigned)
            default: branch_taken = 1'b0;
        endcase
    end

    // ── PC targets ────────────────────────────────────────────
    assign pc_branch = pc + imm_ext;               // branch / JAL
    assign pc_jalr   = (rf_rd1 + imm_ext) & ~32'b1; // JALR: clear LSB

    // PC mux priority: jalr > jump(JAL) > branch > PC+4
    assign pc_next = jalr_sig              ? pc_jalr   :
                     jump                  ? pc_branch  :
                     (branch & branch_taken) ? pc_branch :
                     pc_plus4;

    always @(posedge clk) begin
        if (rst) pc <= 32'b0;
        else     pc <= pc_next;
    end

    // ── Write-back mux ────────────────────────────────────────
    // Priority: MAC > mem_to_reg > jump(link) > ALU
    assign result_wb = mac_op    ? mac_result  :
                       mem_to_reg ? dmem_rd     :
                       jump       ? pc_plus4    :  // JAL/JALR save PC+4
                       alu_result;

endmodule