// ============================================================
// riscv_pipeline.v  —  5-Stage Pipelined RV32I + MUL + MAC Processor
// (ECALL/EBREAK decode as no-ops: there is no trap/CSR support.
//  FENCE is a no-op, which is correct for a single in-order hart.)
// ============================================================
module riscv_pipeline #(
    parameter MEM_AW = 8    // instruction/data memory size: 2^MEM_AW words each
) (
    input  wire        clk,
    input  wire        rst,
`ifdef FPGA_PROG_PORT
    // Program-load port, FPGA builds only (see Imem.v and synth/)
    input  wire        prog_we,
    input  wire [MEM_AW-1:0] prog_addr,
    input  wire [31:0] prog_data,
`endif
    output wire [31:0] pc_out
);

// ── Forward declarations ─────────────────────────────────────
    wire        wb_reg_write;
    wire [4:0]  wb_rd;
    wire [31:0] wb_result;
    wire        mem_reg_write;
    wire [4:0]  mem_rd;
    wire [31:0] mem_alu_result;
    wire [31:0] mem_mac_result;
    wire        stall_pc;
    wire        flush_if_id;
    wire        flush_id_ex;
    wire        branch_taken_ex;
    wire        jump_ex;
    wire        jalr_ex;
    wire [31:0] pc_branch_ex;
    wire [31:0] pc_jalr_ex;

// ================================================================
// IF STAGE
// ================================================================
    reg  [31:0] pc_if;
    wire [31:0] pc_plus4_if = pc_if + 32'd4;
    assign pc_out = pc_if;

    wire [31:0] pc_next =
        jalr_ex         ? pc_jalr_ex   :
        jump_ex         ? pc_branch_ex :
        branch_taken_ex ? pc_branch_ex :
                          pc_plus4_if;

    always @(posedge clk) begin
        if (rst)            pc_if <= 32'b0;
        else if (!stall_pc) pc_if <= pc_next;
    end

    wire [31:0] instr_if;
`ifdef FPGA_SYNC_MEM
    // Block-RAM-friendly memory (registered read address, e.g. MAX 10 M9K);
    // cycle-for-cycle identical to imem.v, see imem_sync.v
    imem_sync #(.AW(MEM_AW)) u_imem (
        .clk(clk), .rst(rst), .en(!stall_pc), .next_addr(pc_next),
  `ifdef FPGA_PROG_PORT
        .we(prog_we), .waddr(prog_addr), .wdata(prog_data),
  `else
        .we(1'b0), .waddr({MEM_AW{1'b0}}), .wdata(32'b0),
  `endif
        .instr(instr_if)
    );
`else
    imem #(.AW(MEM_AW)) u_imem (
  `ifdef FPGA_PROG_PORT
        .clk(clk), .we(prog_we), .waddr(prog_addr), .wdata(prog_data),
  `endif
        .addr(pc_if), .instr(instr_if)
    );
`endif

// ================================================================
// IF/ID REGISTER
// ================================================================
    wire [31:0] if_id_pc, if_id_pc4, if_id_instr;

    if_id_reg u_if_id (
        .clk(clk), .rst(rst),
        .stall(stall_pc),   .flush(flush_if_id),
        .pc_in(pc_if),      .pc_plus4_in(pc_plus4_if),
        .instr_in(instr_if),
        .pc_out(if_id_pc),  .pc_plus4_out(if_id_pc4),
        .instr_out(if_id_instr)
    );

// ================================================================
// ID STAGE
// ================================================================
    wire [6:0] id_opcode   = if_id_instr[6:0];
    wire [4:0] id_rs1      = if_id_instr[19:15];
    wire [4:0] id_rs2      = if_id_instr[24:20];
    wire [4:0] id_rd       = if_id_instr[11:7];
    wire [2:0] id_funct3   = if_id_instr[14:12];
    wire       id_funct7_5 = if_id_instr[30];

    wire        id_reg_write, id_alu_src, id_mem_write, id_mem_read;
    wire        id_mem_to_reg, id_branch, id_jump, id_jalr;
    wire        id_lui_op, id_mac_op;
    wire [1:0]  id_alu_op;
    wire [3:0]  id_alu_ctrl;

    main_decoder u_mdec (
        .opcode(id_opcode),
        .reg_write(id_reg_write),   .alu_src(id_alu_src),
        .mem_write(id_mem_write),   .mem_read(id_mem_read),
        .mem_to_reg(id_mem_to_reg), .branch(id_branch),
        .jump(id_jump),             .jalr(id_jalr),
        .lui_op(id_lui_op),         .mac_op(id_mac_op),
        .alu_op(id_alu_op)
    );

    alu_decoder u_adec (
        .alu_op(id_alu_op),     .funct3(id_funct3),
        .funct7_5(id_funct7_5), .funct7_1(if_id_instr[25]), .opcode_5(id_opcode[5]),
        .lui_op(id_lui_op),     .alu_ctrl(id_alu_ctrl)
    );

    wire [31:0] id_imm_ext;
    imm_gen u_imm (.instr(if_id_instr), .imm_ext(id_imm_ext));

    wire [31:0] id_rd1, id_rd2;
    wire [4:0]  ex_rd;          // declared here: used by the accumulator read port below
    wire [31:0] rf_acc;         // MAC accumulator read (EX stage reads its own rd)
    regfile u_rf (
        .clk(clk),    .we3(wb_reg_write),
        .ra1(id_rs1), .ra2(id_rs2), .ra_acc(ex_rd),
        .wa3(wb_rd),  .wd3(wb_result),
        .rd1(id_rd1), .rd2(id_rd2), .rd_acc(rf_acc)
    );

// ================================================================
// ID/EX REGISTER
// ================================================================
    wire        ex_reg_write, ex_alu_src, ex_mem_write, ex_mem_read;
    wire        ex_mem_to_reg, ex_branch, ex_jump, ex_jalr;
    wire        ex_lui_op, ex_mac_op;
    wire [3:0]  ex_alu_ctrl;
    wire [31:0] ex_pc, ex_pc4, ex_rd1, ex_rd2, ex_imm;
    wire [4:0]  ex_rs1, ex_rs2;

    id_ex_reg u_id_ex (
        .clk(clk), .rst(rst), .flush(flush_id_ex),
        .reg_write_in(id_reg_write),   .alu_src_in(id_alu_src),
        .mem_write_in(id_mem_write),   .mem_read_in(id_mem_read),
        .mem_to_reg_in(id_mem_to_reg), .branch_in(id_branch),
        .jump_in(id_jump),             .jalr_in(id_jalr),
        .lui_op_in(id_lui_op),         .mac_op_in(id_mac_op),
        .alu_ctrl_in(id_alu_ctrl),
        .pc_in(if_id_pc),              .pc_plus4_in(if_id_pc4),
        .rd1_in(id_rd1),               .rd2_in(id_rd2),
        .imm_ext_in(id_imm_ext),
        .rs1_in(id_rs1),               .rs2_in(id_rs2),
        .rd_in(id_rd),
        .reg_write_out(ex_reg_write),  .alu_src_out(ex_alu_src),
        .mem_write_out(ex_mem_write),  .mem_read_out(ex_mem_read),
        .mem_to_reg_out(ex_mem_to_reg),.branch_out(ex_branch),
        .jump_out(ex_jump),            .jalr_out(ex_jalr),
        .lui_op_out(ex_lui_op),        .mac_op_out(ex_mac_op),
        .alu_ctrl_out(ex_alu_ctrl),
        .pc_out(ex_pc),                .pc_plus4_out(ex_pc4),
        .rd1_out(ex_rd1),              .rd2_out(ex_rd2),
        .imm_ext_out(ex_imm),
        .rs1_out(ex_rs1),              .rs2_out(ex_rs2),
        .rd_out(ex_rd)
    );

// ================================================================
// EX STAGE
// ================================================================

    // funct3 shadow latch for branch condition
    reg [2:0] ex_funct3;
    always @(posedge clk) begin
        if (rst || flush_id_ex) ex_funct3 <= 3'b0;
        else                    ex_funct3 <= id_funct3;
    end

    // AUIPC flag shadow latch (the A-operand mux below runs in EX, so it must
    // use the EX-stage instruction, not the one currently in ID)
    reg ex_auipc;
    always @(posedge clk) begin
        if (rst || flush_id_ex) ex_auipc <= 1'b0;
        else                    ex_auipc <= (id_opcode == 7'b0010111);
    end

    // Forwarding unit
    wire [1:0] fwd_a, fwd_b;
    forward_unit u_fwd (
        .id_ex_rs1(ex_rs1),         .id_ex_rs2(ex_rs2),
        .ex_mem_rd(mem_rd),          .ex_mem_reg_write(mem_reg_write),
        .mem_wb_rd(wb_rd),           .mem_wb_reg_write(wb_reg_write),
        .forward_a(fwd_a),           .forward_b(fwd_b)
    );

    // EX/MEM forward value: the registered ALU result. A load or MUL/MAC
    // in MEM has no result yet; the hazard unit stalls any instruction
    // that needs one, so this path never has to carry them (and stays
    // short: a register, no multiplier or adder in front of it).
    wire [31:0] ex_mem_fwd = mem_alu_result;

    // Forwarding muxes
    wire [31:0] fwd_a_val =
        (fwd_a == 2'b10) ? ex_mem_fwd :
        (fwd_a == 2'b01) ? wb_result  :
        ex_rd1;

    wire [31:0] fwd_b_val =
        (fwd_b == 2'b10) ? ex_mem_fwd :
        (fwd_b == 2'b01) ? wb_result  :
        ex_rd2;

    // ALU source A: AUIPC uses PC, everything else uses fwd_a_val
    wire [31:0] alu_in_a = ex_auipc ? ex_pc : fwd_a_val;

    // ALU source B: immediate or forwarded rs2
    wire [31:0] alu_in_b = ex_alu_src ? ex_imm : fwd_b_val;

    // ALU
    wire [31:0] ex_alu_result;
    wire        ex_zero, ex_neg, ex_ovf;

    // HAS_MUL=0: the multiply lives in mul_pipe (split across EX and MEM)
    alu #(.HAS_MUL(0)) u_alu (
        .src_a(alu_in_a),       .src_b(alu_in_b),
        .alu_ctrl(ex_alu_ctrl),
        .result(ex_alu_result),
        .zero(ex_zero), .negative(ex_neg), .overflow(ex_ovf)
    );

    // Multiplier stage 1: 16x16 partial products, registered at the end
    // of EX (stage 2 completes the product in MEM, see mul_pipe.v).
    // MUL/MAC never use the immediate or PC operands, so the forwarded
    // register values feed the multiplier directly.
    wire [31:0] mem_product;
    mul_pipe u_mul (.clk(clk), .a(fwd_a_val), .b(fwd_b_val), .prod(mem_product));

    wire ex_mul = (ex_alu_ctrl == 4'b1010);   // MUL or MAC

    // JAL/JALR link value: PC+4 passed as alu_result into pipeline.
    // (For MUL/MAC the ALU outputs 0; their result is formed in MEM.)
    wire [31:0] ex_result_final =
        ex_jump ? ex_pc4 :         // JAL/JALR: save return address
        ex_alu_result;             // everything else

    // Branch comparator
    wire blt  = ($signed(fwd_a_val) <  $signed(fwd_b_val));
    wire bge  = ($signed(fwd_a_val) >= $signed(fwd_b_val));

    reg branch_cond;
    always @(*) begin
        case (ex_funct3)
            3'b000:  branch_cond = (fwd_a_val == fwd_b_val);
            3'b001:  branch_cond = (fwd_a_val != fwd_b_val);
            3'b100:  branch_cond = blt;
            3'b101:  branch_cond = bge;
            3'b110:  branch_cond = (fwd_a_val <  fwd_b_val);
            3'b111:  branch_cond = (fwd_a_val >= fwd_b_val);
            default: branch_cond = 1'b0;
        endcase
    end

    assign branch_taken_ex = ex_branch && branch_cond;
    assign jump_ex         = ex_jump;
    assign jalr_ex         = ex_jalr;
    assign pc_branch_ex    = ex_pc + ex_imm;
    assign pc_jalr_ex      = (fwd_a_val + ex_imm) & ~32'b1;

// ================================================================
// EX/MEM REGISTER
// ================================================================
    wire        mem_mem_write, mem_mem_read, mem_mem_to_reg, mem_mac_op;
    wire [31:0] mem_pc4, mem_write_data;

    ex_mem_reg u_ex_mem (
        .clk(clk), .rst(rst),
        .reg_write_in(ex_reg_write),    .mem_write_in(ex_mem_write),
        .mem_read_in(ex_mem_read),      .mem_to_reg_in(ex_mem_to_reg),
        .mac_op_in(ex_mac_op),
        .pc_plus4_in(ex_pc4),
        .alu_result_in(ex_result_final),.mac_result_in(ex_result_final),
        .write_data_in(fwd_b_val),      .rd_in(ex_rd),
        .reg_write_out(mem_reg_write),  .mem_write_out(mem_mem_write),
        .mem_read_out(mem_mem_read),    .mem_to_reg_out(mem_mem_to_reg),
        .mac_op_out(mem_mac_op),
        .pc_plus4_out(mem_pc4),
        .alu_result_out(mem_alu_result),.mac_result_out(mem_mac_result),
        .write_data_out(mem_write_data),.rd_out(mem_rd)
    );

// ================================================================
// MEM STAGE
// ================================================================
    // funct3 of the instruction now in MEM (load/store width and signedness).
    // The EX/MEM register is never stalled or flushed, so a plain latch suffices.
    reg [2:0] mem_funct3;
    always @(posedge clk) begin
        if (rst) mem_funct3 <= 3'b0;
        else     mem_funct3 <= ex_funct3;
    end

    // ── Multiplier stage 2 and MAC accumulate ───────────────────────
    // mem_acc: the accumulator (rd) as read in EX through the register
    // file's third port (which already includes any write happening in WB
    // that cycle, via write-through).
    // If the instruction just ahead of this MAC (now in WB) writes rd, its
    // value is forwarded here, WB -> MEM. So a load, MUL or MAC feeding the
    // accumulator never stalls, and MAC chains issue back to back.
    reg        mem_mul;
    reg [31:0] mem_acc;
    always @(posedge clk) begin
        if (rst) begin mem_mul <= 1'b0;   mem_acc <= 32'b0;  end
        else     begin mem_mul <= ex_mul; mem_acc <= rf_acc; end
    end

    wire [31:0] mem_acc_fwd =
        (wb_reg_write && wb_rd == mem_rd && mem_rd != 5'b0) ? wb_result : mem_acc;
    wire [31:0] mem_mul_result = mem_product + (mem_mac_op ? mem_acc_fwd : 32'b0);
    wire [31:0] mem_result     = mem_mul ? mem_mul_result : mem_alu_result;

    wire [31:0] mem_word, mem_rdata, mem_store_data;
    wire [3:0]  mem_byte_en;

    lsu_align u_lsu (
        .funct3(mem_funct3),        .addr_lo(mem_alu_result[1:0]),
        .store_in(mem_write_data),  .load_word(mem_word),
        .store_data(mem_store_data),.byte_en(mem_byte_en),
        .load_data(mem_rdata)
    );

`ifdef FPGA_SYNC_MEM
    // Block-RAM-friendly memory; identical behaviour, see dmem_sync.v
    dmem_sync #(.AW(MEM_AW)) u_dmem (
        .clk(clk),
        .we(mem_mem_write),
        .be(mem_byte_en),
        .waddr(mem_alu_result),
        .wd(mem_store_data),
        .raddr_next(ex_result_final),
        .rd(mem_word)
    );
`else
    dmem #(.AW(MEM_AW)) u_dmem (
        .clk(clk),
        .we(mem_mem_write),
        .be(mem_byte_en),
        .addr(mem_alu_result),
        .wd(mem_store_data),
        .rd(mem_word)
    );
`endif

// ================================================================
// MEM/WB REGISTER
// ================================================================
    wire        wb_mem_to_reg, wb_mac_op;
    wire [31:0] wb_pc4, wb_alu_result, wb_mac_result, wb_mem_data;

    mem_wb_reg u_mem_wb (
        .clk(clk), .rst(rst),
        .reg_write_in(mem_reg_write),   .mem_to_reg_in(mem_mem_to_reg),
        .mac_op_in(mem_mac_op),
        .pc_plus4_in(mem_pc4),
        .alu_result_in(mem_result),     .mac_result_in(mem_result),
        .mem_data_in(mem_rdata),        .rd_in(mem_rd),
        .reg_write_out(wb_reg_write),   .mem_to_reg_out(wb_mem_to_reg),
        .mac_op_out(wb_mac_op),
        .pc_plus4_out(wb_pc4),
        .alu_result_out(wb_alu_result), .mac_result_out(wb_mac_result),
        .mem_data_out(wb_mem_data),     .rd_out(wb_rd)
    );

// ================================================================
// WB STAGE
// ================================================================
    assign wb_result =
        wb_mem_to_reg ? wb_mem_data   :   // loads (already extended in MEM)
        wb_alu_result;                    // ALU, MUL/MAC (formed in MEM), JAL link

// ================================================================
// HAZARD UNIT
// ================================================================
    hazard_unit u_haz (
        .id_ex_mem_read(ex_mem_read),
        .id_ex_mul(ex_mul),
        .id_ex_rd(ex_rd),
        .if_id_rs1(id_rs1),
        .if_id_rs2(id_rs2),
        .branch_taken(branch_taken_ex),
        .jump(ex_jump),
        .stall(stall_pc),
        .flush_if_id(flush_if_id),
        .flush_id_ex(flush_id_ex)
    );

endmodule