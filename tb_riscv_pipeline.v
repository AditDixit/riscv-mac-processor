// ============================================================
// tb_riscv_pipeline.v  —  Full pipeline test
//
// Test programs (loaded directly into imem):
//
// TEST 1 — Basic ALU + EX-EX forwarding
//   addi x1, x0, 10      // x1 = 10
//   addi x2, x0, 3       // x2 = 3
//   add  x3, x1, x2      // x3 = 13  (EX-EX fwd x1, x2)
//   sub  x4, x3, x2      // x4 = 10  (EX-EX fwd x3, MEM-EX fwd x2)
//   and  x5, x1, x2      // x5 = 2
//   or   x6, x1, x2      // x6 = 11
//   xor  x7, x1, x2      // x7 = 9
//   sll  x8, x2, x2      // x8 = 24  (3 << 3)
//
// TEST 2 — Load-use stall
//   sw   x1, 0(x0)       // mem[0] = 10
//   lw   x9, 0(x0)       // x9 = 10  (load)
//   nop                   // ← hazard unit inserts bubble here
//   add  x10, x9, x1     // x10 = 20 (uses x9 after stall)
//
// TEST 3 — Branch taken (BEQ)
//   addi x11, x0, 5
//   addi x12, x0, 5
//   beq  x11, x12, +8    // taken → skip next instruction
//   addi x13, x0, 99     // SKIPPED
//   addi x13, x0, 77     // x13 = 77
//
// TEST 4 — MAC accumulate
//   addi x1, x0, 4       // reuse x1 = 4
//   addi x2, x0, 5       // reuse x2 = 5
//   mac  x14, x1, x2     // x14 = 0 + 4*5 = 20
//   mac  x14, x1, x2     // x14 = 20 + 4*5 = 40
//   mac  x14, x1, x2     // x14 = 40 + 4*5 = 60
//
// Run:
//   iverilog -o tb_pip tb_riscv_pipeline.v riscv_pipeline.v \
//            pipeline_regs.v hazard_unit.v forward_unit.v \
//            imem.v dmem.v regfile.v alu.v control.v
//   vvp tb_pip
// ============================================================
`timescale 1ns/1ps

module tb_riscv_pipeline;

    reg clk = 0, rst = 1;
    always #5 clk = ~clk;

    wire [31:0] pc_out;
    riscv_pipeline uut (.clk(clk), .rst(rst), .pc_out(pc_out));

    `define RF  uut.u_rf.rf
    `define MEM uut.u_dmem.mem

    integer errors = 0;
    integer i;

    task chk;
        input [31:0] got, exp;
        input [8*36:1] label;
        begin
            if (got !== exp) begin
                $display("FAIL  %-36s got=%0d  exp=%0d", label, got, exp);
                errors = errors + 1;
            end else
                $display("PASS  %-36s = %0d", label, got);
        end
    endtask

    // Encode R-type instruction
    function [31:0] rtype;
        input [6:0] funct7;
        input [4:0] rs2, rs1;
        input [2:0] funct3;
        input [4:0] rd;
        input [6:0] opcode;
        rtype = {funct7, rs2, rs1, funct3, rd, opcode};
    endfunction

    // Encode I-type instruction
    function [31:0] itype;
        input [11:0] imm;
        input [4:0]  rs1;
        input [2:0]  funct3;
        input [4:0]  rd;
        input [6:0]  opcode;
        itype = {imm, rs1, funct3, rd, opcode};
    endfunction

    // Encode B-type: imm_bytes is the raw signed byte offset
    function [31:0] btype;
        input [31:0] imm_bytes;   // raw byte offset (e.g. +8, -4)
        input [4:0]  rs2, rs1;
        input [2:0]  funct3;
        input [6:0]  opcode;
        reg [12:0] imm;
        begin
            imm = imm_bytes[12:0];   // take lower 13 bits
            btype = {imm[12], imm[10:5], rs2, rs1, funct3,
                     imm[4:1], imm[11], opcode};
        end
    endfunction

    // Encode S-type instruction
    function [31:0] stype;
        input [11:0] imm;
        input [4:0]  rs2, rs1;
        input [2:0]  funct3;
        input [6:0]  opcode;
        stype = {imm[11:5], rs2, rs1, funct3, imm[4:0], opcode};
    endfunction

    localparam OP_ARITH = 7'b0110011;
    localparam OP_IARITH= 7'b0010011;
    localparam OP_LOAD  = 7'b0000011;
    localparam OP_STORE = 7'b0100011;
    localparam OP_BRANCH= 7'b1100011;
    localparam OP_MAC   = 7'b0001011;
    localparam NOP      = 32'h00000013;

    initial begin
        // clear memories
        for (i = 0; i < 256; i = i + 1) begin
            uut.u_imem.mem[i] = NOP;
            uut.u_dmem.mem[i] = 32'b0;
        end

        // ── TEST 1: ALU + EX-EX forwarding ─────────────────
        // addr 0
        uut.u_imem.mem[0]  = itype(12'd10, 5'd0, 3'b000, 5'd1,  OP_IARITH); // addi x1,x0,10
        uut.u_imem.mem[1]  = itype(12'd3,  5'd0, 3'b000, 5'd2,  OP_IARITH); // addi x2,x0,3
        uut.u_imem.mem[2]  = rtype(7'h00,  5'd2, 5'd1, 3'b000, 5'd3,  OP_ARITH); // add x3,x1,x2
        uut.u_imem.mem[3]  = rtype(7'h20,  5'd2, 5'd3, 3'b000, 5'd4,  OP_ARITH); // sub x4,x3,x2
        uut.u_imem.mem[4]  = rtype(7'h00,  5'd2, 5'd1, 3'b111, 5'd5,  OP_ARITH); // and x5,x1,x2
        uut.u_imem.mem[5]  = rtype(7'h00,  5'd2, 5'd1, 3'b110, 5'd6,  OP_ARITH); // or  x6,x1,x2
        uut.u_imem.mem[6]  = rtype(7'h00,  5'd2, 5'd1, 3'b100, 5'd7,  OP_ARITH); // xor x7,x1,x2
        uut.u_imem.mem[7]  = rtype(7'h00,  5'd2, 5'd2, 3'b001, 5'd8,  OP_ARITH); // sll x8,x2,x2

        // ── TEST 2: Load-use stall ──────────────────────────
        uut.u_imem.mem[8]  = stype(12'd0,  5'd1, 5'd0, 3'b010, OP_STORE);   // sw x1,0(x0)
        uut.u_imem.mem[9]  = itype(12'd0,  5'd0, 3'b010, 5'd9, OP_LOAD);    // lw x9,0(x0)
        uut.u_imem.mem[10] = rtype(7'h00,  5'd1, 5'd9, 3'b000, 5'd10, OP_ARITH); // add x10,x9,x1

        // ── TEST 3: Branch taken (BEQ) ──────────────────────
        uut.u_imem.mem[11] = itype(12'd5, 5'd0, 3'b000, 5'd11, OP_IARITH);  // addi x11,x0,5
        uut.u_imem.mem[12] = itype(12'd5, 5'd0, 3'b000, 5'd12, OP_IARITH);  // addi x12,x0,5
        // beq x11,x12,+8  (offset=8 → skip mem[13], land on mem[14])
        uut.u_imem.mem[13] = btype(12'd8, 5'd12, 5'd11, 3'b000, OP_BRANCH);
        uut.u_imem.mem[14] = itype(12'd99,5'd0, 3'b000, 5'd13, OP_IARITH);  // addi x13,x0,99 SKIPPED
        uut.u_imem.mem[15] = itype(12'd77,5'd0, 3'b000, 5'd13, OP_IARITH);  // addi x13,x0,77

        // ── TEST 4: MAC accumulate ──────────────────────────
        uut.u_imem.mem[16] = itype(12'd4, 5'd0, 3'b000, 5'd1,  OP_IARITH);  // addi x1,x0,4
        uut.u_imem.mem[17] = itype(12'd5, 5'd0, 3'b000, 5'd2,  OP_IARITH);  // addi x2,x0,5
        uut.u_imem.mem[18] = rtype(7'h00, 5'd2, 5'd1, 3'b000, 5'd14, OP_MAC); // mac x14,x1,x2
        uut.u_imem.mem[19] = rtype(7'h00, 5'd2, 5'd1, 3'b000, 5'd14, OP_MAC); // mac x14,x1,x2
        uut.u_imem.mem[20] = rtype(7'h00, 5'd2, 5'd1, 3'b000, 5'd14, OP_MAC); // mac x14,x1,x2
        // NOPs fill rest

        // ── Reset release ───────────────────────────────────
        @(posedge clk); #1;
        rst = 0;

        // Run enough cycles (program has ~21 instrs + pipeline depth + stalls)
        // 21 instrs + 4 pipeline stages + 2-cycle branch penalty + 1 load stall = ~35
        repeat(45) @(posedge clk);
        #1;

        // ── Check results ───────────────────────────────────
        $display("\n=== TEST 1: ALU + Forwarding ===");
        chk(`RF[1],  32'd4,  "x1  = 4  (overwritten by TEST4)");
        chk(`RF[2],  32'd5,  "x2  = 5  (overwritten by TEST4)");
        chk(`RF[3],  32'd13, "x3  = 13 (add, EX-EX fwd)");
        chk(`RF[4],  32'd10, "x4  = 10 (sub, EX-EX fwd)");
        chk(`RF[5],  32'd2,  "x5  = 2  (and)");
        chk(`RF[6],  32'd11, "x6  = 11 (or)");
        chk(`RF[7],  32'd9,  "x7  = 9  (xor)");
        chk(`RF[8],  32'd24, "x8  = 24 (sll 3<<3)");

        $display("\n=== TEST 2: Load-Use Stall ===");
        chk(`MEM[0], 32'd10, "mem[0] = 10 (sw)");
        chk(`RF[9],  32'd10, "x9  = 10 (lw after stall)");
        chk(`RF[10], 32'd20, "x10 = 20 (add x9+x1, post-stall fwd)");

        $display("\n=== TEST 3: Branch Taken ===");
        chk(`RF[11], 32'd5,  "x11 = 5");
        chk(`RF[12], 32'd5,  "x12 = 5");
        chk(`RF[13], 32'd77, "x13 = 77 (branch taken, 99 skipped)");

        $display("\n=== TEST 4: MAC Accumulation ===");
        chk(`RF[14], 32'd60, "x14 = 60 (3x MAC: 20+20+20)");

        if (errors == 0)
            $display("\n=== ALL PIPELINE TESTS PASSED ===");
        else
            $display("\n=== %0d FAILURE(S) ===", errors);

        $finish;
    end

endmodule