// ============================================================
// pipeline_regs.v  —  IF/ID, ID/EX, EX/MEM, MEM/WB latches
//
// Each register:
//   - Captures inputs on posedge clk
//   - Synchronous reset → inserts NOP bubble (all zeros)
//   - stall input holds current values (pipeline freeze)
//   - flush input clears to NOP bubble (branch misprediction)
//
// NOP = addi x0, x0, 0  (all control signals = 0, rd = 0)
// ============================================================

// ------------------------------------------------------------
// IF/ID  —  Instruction Fetch → Instruction Decode
// Carries: PC, PC+4, raw instruction word
// ------------------------------------------------------------
module if_id_reg (
    input  wire        clk, rst,
    input  wire        stall,       // 1 = hold current values
    input  wire        flush,       // 1 = insert NOP bubble
    // Inputs (from IF stage)
    input  wire [31:0] pc_in,
    input  wire [31:0] pc_plus4_in,
    input  wire [31:0] instr_in,
    // Outputs (to ID stage)
    output reg  [31:0] pc_out,
    output reg  [31:0] pc_plus4_out,
    output reg  [31:0] instr_out
);
    always @(posedge clk) begin
        if (rst || flush) begin
            pc_out       <= 32'b0;
            pc_plus4_out <= 32'b0;
            instr_out    <= 32'h00000013;  // NOP
        end else if (!stall) begin
            pc_out       <= pc_in;
            pc_plus4_out <= pc_plus4_in;
            instr_out    <= instr_in;
        end
        // stall: outputs unchanged (implicit else)
    end
endmodule


// ------------------------------------------------------------
// ID/EX  —  Instruction Decode → Execute
// Carries: control signals, register values, immediate, rd/rs fields
// ------------------------------------------------------------
module id_ex_reg (
    input  wire        clk, rst,
    input  wire        flush,       // 1 = insert NOP bubble
    // Control signals
    input  wire        reg_write_in,
    input  wire        alu_src_in,
    input  wire        mem_write_in,
    input  wire        mem_read_in,
    input  wire        mem_to_reg_in,
    input  wire        branch_in,
    input  wire        jump_in,
    input  wire        jalr_in,
    input  wire        lui_op_in,
    input  wire        mac_op_in,
    input  wire [3:0]  alu_ctrl_in,
    // Data
    input  wire [31:0] pc_in,
    input  wire [31:0] pc_plus4_in,
    input  wire [31:0] rd1_in,      // rs1 value
    input  wire [31:0] rd2_in,      // rs2 value
    input  wire [31:0] imm_ext_in,
    input  wire [4:0]  rs1_in,
    input  wire [4:0]  rs2_in,
    input  wire [4:0]  rd_in,
    // Outputs
    output reg         reg_write_out,
    output reg         alu_src_out,
    output reg         mem_write_out,
    output reg         mem_read_out,
    output reg         mem_to_reg_out,
    output reg         branch_out,
    output reg         jump_out,
    output reg         jalr_out,
    output reg         lui_op_out,
    output reg         mac_op_out,
    output reg  [3:0]  alu_ctrl_out,
    output reg  [31:0] pc_out,
    output reg  [31:0] pc_plus4_out,
    output reg  [31:0] rd1_out,
    output reg  [31:0] rd2_out,
    output reg  [31:0] imm_ext_out,
    output reg  [4:0]  rs1_out,
    output reg  [4:0]  rs2_out,
    output reg  [4:0]  rd_out
);
    always @(posedge clk) begin
        if (rst || flush) begin
            // Insert NOP bubble — clear all control signals
            reg_write_out  <= 1'b0;
            alu_src_out    <= 1'b0;
            mem_write_out  <= 1'b0;
            mem_read_out   <= 1'b0;
            mem_to_reg_out <= 1'b0;
            branch_out     <= 1'b0;
            jump_out       <= 1'b0;
            jalr_out       <= 1'b0;
            lui_op_out     <= 1'b0;
            mac_op_out     <= 1'b0;
            alu_ctrl_out   <= 4'b0;
            pc_out         <= 32'b0;
            pc_plus4_out   <= 32'b0;
            rd1_out        <= 32'b0;
            rd2_out        <= 32'b0;
            imm_ext_out    <= 32'b0;
            rs1_out        <= 5'b0;
            rs2_out        <= 5'b0;
            rd_out         <= 5'b0;
        end else begin
            reg_write_out  <= reg_write_in;
            alu_src_out    <= alu_src_in;
            mem_write_out  <= mem_write_in;
            mem_read_out   <= mem_read_in;
            mem_to_reg_out <= mem_to_reg_in;
            branch_out     <= branch_in;
            jump_out       <= jump_in;
            jalr_out       <= jalr_in;
            lui_op_out     <= lui_op_in;
            mac_op_out     <= mac_op_in;
            alu_ctrl_out   <= alu_ctrl_in;
            pc_out         <= pc_in;
            pc_plus4_out   <= pc_plus4_in;
            rd1_out        <= rd1_in;
            rd2_out        <= rd2_in;
            imm_ext_out    <= imm_ext_in;
            rs1_out        <= rs1_in;
            rs2_out        <= rs2_in;
            rd_out         <= rd_in;
        end
    end
endmodule


// ------------------------------------------------------------
// EX/MEM  —  Execute → Memory
// Carries: control signals, ALU result, write data, rd
// ------------------------------------------------------------
module ex_mem_reg (
    input  wire        clk, rst,
    // Control
    input  wire        reg_write_in,
    input  wire        mem_write_in,
    input  wire        mem_read_in,
    input  wire        mem_to_reg_in,
    input  wire        mac_op_in,
    // Data
    input  wire [31:0] pc_plus4_in,
    input  wire [31:0] alu_result_in,
    input  wire [31:0] mac_result_in,
    input  wire [31:0] write_data_in,  // rs2 value (for SW)
    input  wire [4:0]  rd_in,
    // Outputs
    output reg         reg_write_out,
    output reg         mem_write_out,
    output reg         mem_read_out,
    output reg         mem_to_reg_out,
    output reg         mac_op_out,
    output reg  [31:0] pc_plus4_out,
    output reg  [31:0] alu_result_out,
    output reg  [31:0] mac_result_out,
    output reg  [31:0] write_data_out,
    output reg  [4:0]  rd_out
);
    always @(posedge clk) begin
        if (rst) begin
            reg_write_out  <= 1'b0;
            mem_write_out  <= 1'b0;
            mem_read_out   <= 1'b0;
            mem_to_reg_out <= 1'b0;
            mac_op_out     <= 1'b0;
            pc_plus4_out   <= 32'b0;
            alu_result_out <= 32'b0;
            mac_result_out <= 32'b0;
            write_data_out <= 32'b0;
            rd_out         <= 5'b0;
        end else begin
            reg_write_out  <= reg_write_in;
            mem_write_out  <= mem_write_in;
            mem_read_out   <= mem_read_in;
            mem_to_reg_out <= mem_to_reg_in;
            mac_op_out     <= mac_op_in;
            pc_plus4_out   <= pc_plus4_in;
            alu_result_out <= alu_result_in;
            mac_result_out <= mac_result_in;
            write_data_out <= write_data_in;
            rd_out         <= rd_in;
        end
    end
endmodule


// ------------------------------------------------------------
// MEM/WB  —  Memory → Writeback
// Carries: control signals, memory read data, ALU result, rd
// ------------------------------------------------------------
module mem_wb_reg (
    input  wire        clk, rst,
    // Control
    input  wire        reg_write_in,
    input  wire        mem_to_reg_in,
    input  wire        mac_op_in,
    // Data
    input  wire [31:0] pc_plus4_in,
    input  wire [31:0] alu_result_in,
    input  wire [31:0] mac_result_in,
    input  wire [31:0] mem_data_in,
    input  wire [4:0]  rd_in,
    // Outputs
    output reg         reg_write_out,
    output reg         mem_to_reg_out,
    output reg         mac_op_out,
    output reg  [31:0] pc_plus4_out,
    output reg  [31:0] alu_result_out,
    output reg  [31:0] mac_result_out,
    output reg  [31:0] mem_data_out,
    output reg  [4:0]  rd_out
);
    always @(posedge clk) begin
        if (rst) begin
            reg_write_out  <= 1'b0;
            mem_to_reg_out <= 1'b0;
            mac_op_out     <= 1'b0;
            pc_plus4_out   <= 32'b0;
            alu_result_out <= 32'b0;
            mac_result_out <= 32'b0;
            mem_data_out   <= 32'b0;
            rd_out         <= 5'b0;
        end else begin
            reg_write_out  <= reg_write_in;
            mem_to_reg_out <= mem_to_reg_in;
            mac_op_out     <= mac_op_in;
            pc_plus4_out   <= pc_plus4_in;
            alu_result_out <= alu_result_in;
            mac_result_out <= mac_result_in;
            mem_data_out   <= mem_data_in;
            rd_out         <= rd_in;
        end
    end
endmodule