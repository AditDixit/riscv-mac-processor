// ============================================================
// tb_benchmark.v  —  MAC vs Standard dot-product benchmark
//
// Computes dot product of two 8-element vectors:
//   A = [1, 2, 3, 4, 5, 6, 7, 8]
//   B = [8, 7, 6, 5, 4, 3, 2, 1]
//   Expected result = 1*8+2*7+3*6+4*5+5*4+6*3+7*2+8*1 = 120
//
// Two programs run back-to-back:
//
// PROGRAM 1 — Standard (mul + add):
//   Uses M-extension MUL then ADD for each element.
//   mul  t0, a0, b0
//   add  acc, acc, t0    ← two instructions per element
//   ...
//   Total: 2 instrs × 8 elements = 16 arithmetic instrs
//
// PROGRAM 2 — MAC accelerated:
//   mac  acc, a0, b0     ← one instruction per element
//   ...
//   Total: 1 instr × 8 elements = 8 arithmetic instrs
//
// Cycle counting: we count from first arithmetic instruction
// to the cycle the final result is written back to rd.
// We use the PC to detect start and end.
//
// Run:
//   iverilog -o tb_bench tb_benchmark.v riscv_pipeline.v \
//            pipeline_regs.v hazard_unit.v forward_unit.v \
//            imem.v dmem.v regfile.v alu.v control.v
//   vvp tb_bench
// ============================================================
`timescale 1ns/1ps

module tb_benchmark;

    reg clk = 0, rst = 1;
    always #5 clk = ~clk;

    wire [31:0] pc_out;
    riscv_pipeline uut (.clk(clk), .rst(rst), .pc_out(pc_out));

    `define RF  uut.u_rf.rf
    `define MEM uut.u_dmem.mem

    integer i;

    // Cycle counters
    integer cycle_total;
    integer std_start, std_end, std_cycles;
    integer mac_start, mac_end, mac_cycles;

    // PC boundaries (byte addresses)
    // Standard program: instructions at mem[0..19]  → PC 0..76
    // MAC program:      instructions at mem[32..51] → PC 128..204
    localparam STD_FIRST_PC  = 32'd20;   // first mul instruction
    localparam STD_LAST_PC   = 32'd76;   // last add instruction  
    localparam MAC_FIRST_PC  = 32'd148;  // first mac instruction
    localparam MAC_LAST_PC   = 32'd176;  // last mac instruction

    // ── Instruction encoders ─────────────────────────────────
    function [31:0] itype;
        input [11:0] imm; input [4:0] rs1; input [2:0] f3;
        input [4:0] rd;   input [6:0] op;
        itype = {imm, rs1, f3, rd, op};
    endfunction

    function [31:0] rtype;
        input [6:0] f7; input [4:0] rs2,rs1; input [2:0] f3;
        input [4:0] rd; input [6:0] op;
        rtype = {f7, rs2, rs1, f3, rd, op};
    endfunction

    function [31:0] stype;
        input [11:0] imm; input [4:0] rs2,rs1; input [2:0] f3;
        input [6:0] op;
        stype = {imm[11:5], rs2, rs1, f3, imm[4:0], op};
    endfunction

    localparam OP_ARITH  = 7'b0110011;
    localparam OP_IARITH = 7'b0010011;
    localparam OP_LOAD   = 7'b0000011;
    localparam OP_STORE  = 7'b0100011;
    localparam OP_MAC    = 7'b0001011;
    localparam NOP       = 32'h00000013;

    // Register aliases (by number)
    // x1=acc  x2=tmp  x10-x17=A[0..7]  x18-x25=B[0..7]

    integer ci;  // cycle index

    initial begin
        // ── Clear memories ──────────────────────────────────
        for (i = 0; i < 256; i = i + 1) begin
            uut.u_imem.mem[i] = NOP;
            uut.u_dmem.mem[i] = 32'b0;
        end

        // ================================================================
        // PROGRAM 1 — Standard multiply-accumulate (mul + add)
        // mem[0..4]   : load A and B values into registers
        // mem[5..19]  : mul+add pairs for 8 elements
        // ================================================================

        // --- Setup: load A[0..7] into x10..x17, B[0..7] into x18..x25 ---
        // A = [1,2,3,4,5,6,7,8]
        uut.u_imem.mem[0]  = itype(12'd1, 5'd0, 3'b000, 5'd10, OP_IARITH); // addi x10,x0,1
        uut.u_imem.mem[1]  = itype(12'd2, 5'd0, 3'b000, 5'd11, OP_IARITH); // addi x11,x0,2
        uut.u_imem.mem[2]  = itype(12'd3, 5'd0, 3'b000, 5'd12, OP_IARITH); // addi x12,x0,3
        uut.u_imem.mem[3]  = itype(12'd4, 5'd0, 3'b000, 5'd13, OP_IARITH); // addi x13,x0,4
        uut.u_imem.mem[4]  = itype(12'd5, 5'd0, 3'b000, 5'd14, OP_IARITH); // addi x14,x0,5
        uut.u_imem.mem[5]  = itype(12'd6, 5'd0, 3'b000, 5'd15, OP_IARITH); // addi x15,x0,6
        uut.u_imem.mem[6]  = itype(12'd7, 5'd0, 3'b000, 5'd16, OP_IARITH); // addi x16,x0,7
        uut.u_imem.mem[7]  = itype(12'd8, 5'd0, 3'b000, 5'd17, OP_IARITH); // addi x17,x0,8
        // B = [8,7,6,5,4,3,2,1]
        uut.u_imem.mem[8]  = itype(12'd8, 5'd0, 3'b000, 5'd18, OP_IARITH); // addi x18,x0,8
        uut.u_imem.mem[9]  = itype(12'd7, 5'd0, 3'b000, 5'd19, OP_IARITH); // addi x19,x0,7
        uut.u_imem.mem[10] = itype(12'd6, 5'd0, 3'b000, 5'd20, OP_IARITH); // addi x20,x0,6
        uut.u_imem.mem[11] = itype(12'd5, 5'd0, 3'b000, 5'd21, OP_IARITH); // addi x21,x0,5
        uut.u_imem.mem[12] = itype(12'd4, 5'd0, 3'b000, 5'd22, OP_IARITH); // addi x22,x0,4
        uut.u_imem.mem[13] = itype(12'd3, 5'd0, 3'b000, 5'd23, OP_IARITH); // addi x23,x0,3
        uut.u_imem.mem[14] = itype(12'd2, 5'd0, 3'b000, 5'd24, OP_IARITH); // addi x24,x0,2
        uut.u_imem.mem[15] = itype(12'd1, 5'd0, 3'b000, 5'd25, OP_IARITH); // addi x25,x0,1
        // x1 = accumulator, clear to 0
        uut.u_imem.mem[16] = itype(12'd0, 5'd0, 3'b000, 5'd1,  OP_IARITH); // addi x1,x0,0

        // --- Standard dot product: mul x2,ai,bi then add x1,x1,x2 ---
        // STD_FIRST_PC = mem[17] = 17*4 = 68... let me adjust
        // Actually mem indices: setup is [0..16], mul+add starts at [17]
        // STD_FIRST_PC = 17*4 = 68
        uut.u_imem.mem[17] = rtype(7'h01,5'd18,5'd10,3'b000,5'd2,OP_ARITH); // mul x2,x10,x18
        uut.u_imem.mem[18] = rtype(7'h00,5'd2, 5'd1, 3'b000,5'd1,OP_ARITH); // add x1,x1,x2
        uut.u_imem.mem[19] = rtype(7'h01,5'd19,5'd11,3'b000,5'd2,OP_ARITH); // mul x2,x11,x19
        uut.u_imem.mem[20] = rtype(7'h00,5'd2, 5'd1, 3'b000,5'd1,OP_ARITH); // add x1,x1,x2
        uut.u_imem.mem[21] = rtype(7'h01,5'd20,5'd12,3'b000,5'd2,OP_ARITH); // mul x2,x12,x20
        uut.u_imem.mem[22] = rtype(7'h00,5'd2, 5'd1, 3'b000,5'd1,OP_ARITH); // add x1,x1,x2
        uut.u_imem.mem[23] = rtype(7'h01,5'd21,5'd13,3'b000,5'd2,OP_ARITH); // mul x2,x13,x21
        uut.u_imem.mem[24] = rtype(7'h00,5'd2, 5'd1, 3'b000,5'd1,OP_ARITH); // add x1,x1,x2
        uut.u_imem.mem[25] = rtype(7'h01,5'd22,5'd14,3'b000,5'd2,OP_ARITH); // mul x2,x14,x22
        uut.u_imem.mem[26] = rtype(7'h00,5'd2, 5'd1, 3'b000,5'd1,OP_ARITH); // add x1,x1,x2
        uut.u_imem.mem[27] = rtype(7'h01,5'd23,5'd15,3'b000,5'd2,OP_ARITH); // mul x2,x15,x23
        uut.u_imem.mem[28] = rtype(7'h00,5'd2, 5'd1, 3'b000,5'd1,OP_ARITH); // add x1,x1,x2
        uut.u_imem.mem[29] = rtype(7'h01,5'd24,5'd16,3'b000,5'd2,OP_ARITH); // mul x2,x16,x24
        uut.u_imem.mem[30] = rtype(7'h00,5'd2, 5'd1, 3'b000,5'd1,OP_ARITH); // add x1,x1,x2
        uut.u_imem.mem[31] = rtype(7'h01,5'd25,5'd17,3'b000,5'd2,OP_ARITH); // mul x2,x17,x25
        uut.u_imem.mem[32] = rtype(7'h00,5'd2, 5'd1, 3'b000,5'd1,OP_ARITH); // add x1,x1,x2
        // STD ends at mem[32], PC=128. Pipeline needs 4 more cycles to drain.
        uut.u_imem.mem[33] = NOP;
        uut.u_imem.mem[34] = NOP;
        uut.u_imem.mem[35] = NOP;
        uut.u_imem.mem[36] = NOP;

        // ================================================================
        // PROGRAM 2 — MAC accelerated dot product
        // Starts at mem[40]. Reuse same A/B registers (still loaded).
        // x3 = accumulator for MAC version
        // ================================================================
        // Clear accumulator (x3 is destination of MAC instructions)
        uut.u_imem.mem[37] = itype(12'd0,5'd0,3'b000,5'd3,OP_IARITH); // addi x3,x0,0
        // padding NOPs so MAC starts cleanly
        uut.u_imem.mem[38] = NOP;
        uut.u_imem.mem[39] = NOP;

        // MAC dot product: mac x3, ai, bi  (x3 = x3 + ai*bi)
        uut.u_imem.mem[40] = rtype(7'h00,5'd18,5'd10,3'b000,5'd3,OP_MAC); // mac x3,x10,x18
        uut.u_imem.mem[41] = rtype(7'h00,5'd19,5'd11,3'b000,5'd3,OP_MAC); // mac x3,x11,x19
        uut.u_imem.mem[42] = rtype(7'h00,5'd20,5'd12,3'b000,5'd3,OP_MAC); // mac x3,x12,x20
        uut.u_imem.mem[43] = rtype(7'h00,5'd21,5'd13,3'b000,5'd3,OP_MAC); // mac x3,x13,x21
        uut.u_imem.mem[44] = rtype(7'h00,5'd22,5'd14,3'b000,5'd3,OP_MAC); // mac x3,x14,x22
        uut.u_imem.mem[45] = rtype(7'h00,5'd23,5'd15,3'b000,5'd3,OP_MAC); // mac x3,x15,x23
        uut.u_imem.mem[46] = rtype(7'h00,5'd24,5'd16,3'b000,5'd3,OP_MAC); // mac x3,x16,x24
        uut.u_imem.mem[47] = rtype(7'h00,5'd25,5'd17,3'b000,5'd3,OP_MAC); // mac x3,x17,x25
        // Drain pipeline
        uut.u_imem.mem[48] = NOP;
        uut.u_imem.mem[49] = NOP;
        uut.u_imem.mem[50] = NOP;
        uut.u_imem.mem[51] = NOP;

        // ── Reset ────────────────────────────────────────────
        @(posedge clk); #1; rst = 0;

        // ── Run and count cycles ─────────────────────────────
        std_start = 0; std_end = 0;
        mac_start = 0; mac_end = 0;
        cycle_total = 0;

        // Run 120 cycles — enough for both programs plus drain
        for (ci = 0; ci < 120; ci = ci + 1) begin
            @(posedge clk); #1;
            cycle_total = cycle_total + 1;

            // Standard: starts when first MUL enters pipeline (PC=68)
            if (pc_out == 32'd68  && std_start == 0) std_start = cycle_total;
            // Standard: ends when last ADD writes back (PC=132+4 drain)
            if (pc_out == 32'd136 && std_end   == 0) std_end   = cycle_total;

            // MAC: starts when first MAC enters pipeline (PC=160)
            if (pc_out == 32'd160 && mac_start == 0) mac_start = cycle_total;
            // MAC: ends when last MAC result is drained (PC=196)
            if (pc_out == 32'd196 && mac_end   == 0) mac_end   = cycle_total;
        end

        std_cycles = std_end - std_start;
        mac_cycles = mac_end - mac_start;

        // ── Results ──────────────────────────────────────────
        $display("\n╔══════════════════════════════════════════════╗");
        $display("║         DOT PRODUCT BENCHMARK RESULTS        ║");
        $display("║   A·B = [1..8]·[8..1] = 120 (8 elements)    ║");
        $display("╠══════════════════════════════════════════════╣");
        $display("║ Standard (mul+add):                          ║");
        $display("║   Result  : x1 = %0d %s                    ║",
            `RF[1], (`RF[1]==120) ? "(CORRECT)" : "(WRONG)  ");
        $display("║   Instructions: 16 (8×mul + 8×add)          ║");
        $display("║   Cycles used : %0d                           ║", std_cycles);
        $display("╠══════════════════════════════════════════════╣");
        $display("║ MAC accelerated:                             ║");
        $display("║   Result  : x3 = %0d %s                    ║",
            `RF[3], (`RF[3]==120) ? "(CORRECT)" : "(WRONG)  ");
        $display("║   Instructions: 8  (8×mac)                  ║");
        $display("║   Cycles used : %0d                           ║", mac_cycles);
        $display("╠══════════════════════════════════════════════╣");

        if (std_cycles > 0 && mac_cycles > 0) begin
            $display("║ Speedup: %0d/%0d = %.2fx fewer cycles         ║",
                std_cycles, mac_cycles,
                (1.0*std_cycles)/mac_cycles);
            $display("║ Instruction reduction: 16→8 = 50%%           ║");
        end
        $display("╚══════════════════════════════════════════════╝");

        // Correctness assertions
        if (`RF[1] !== 32'd120)
            $display("FAIL: Standard result wrong: got %0d, exp 120", `RF[1]);
        else
            $display("PASS: Standard dot product = 120");

        if (`RF[3] !== 32'd120)
            $display("FAIL: MAC result wrong: got %0d, exp 120", `RF[3]);
        else
            $display("PASS: MAC dot product = 120");

        $finish;
    end

endmodule