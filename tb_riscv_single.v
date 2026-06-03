// ============================================================
// tb_riscv_single.v  —  End-to-end test for riscv_single
//
// Test program (hand-assembled into program.hex):
//
//   addi x1, x0, 5       # x1 = 5
//   addi x2, x0, 3       # x2 = 3
//   add  x3, x1, x2      # x3 = 8
//   sub  x4, x3, x2      # x4 = 5
//   sw   x3, 0(x0)       # mem[0] = 8
//   lw   x5, 0(x0)       # x5 = 8  (load what we stored)
//   and  x6, x1, x2      # x6 = 5 & 3 = 1
//   or   x7, x1, x2      # x7 = 5 | 3 = 7
//   sll  x8, x1, x2      # x8 = 5 << 3 = 40
//   slt  x9, x2, x1      # x9 = (3 < 5) = 1
//   beq  x6, x9, +8      # x6==x9 (both 1) → skip next instr
//   addi x10, x0, 99     # SKIPPED
//   addi x10, x0, 42     # x10 = 42  (branch target)
//   mac  x11, x1, x2     # x11 = 0 + 5*3 = 15  (MAC #1)
//   mac  x11, x3, x2     # x11 = 15 + 8*3 = 39 (MAC #2, accumulate)
//   nop                   # padding
//
// Run: iverilog -o tb_single tb_riscv_single.v riscv_single.v
//               imem.v dmem.v regfile.v alu.v control.v
//      vvp tb_single
// ============================================================
`timescale 1ns/1ps

module tb_riscv_single;

    reg clk = 0, rst = 1;
    always #5 clk = ~clk;

    wire [31:0] pc_out;
    riscv_single uut (.clk(clk), .rst(rst), .pc_out(pc_out));

    // Give direct access to the register file and data memory
    // for result checking (hierarchical path)
    `define RF  uut.u_rf.rf
    `define MEM uut.u_dmem.mem

    integer errors = 0;

    task chk;
        input [31:0] got, exp;
        input [8*32:1] label;
        begin
            if (got !== exp) begin
                $display("FAIL  %-32s got=%0d (0x%08h)  exp=%0d (0x%08h)",
                         label, got, got, exp, exp);
                errors = errors + 1;
            end else
                $display("PASS  %-32s = %0d", label, got);
        end
    endtask

    // Number of clock cycles to run
    integer cycle;

    initial begin
        // ── Generate the test program hex ──────────────────
        // Each instruction is a 32-bit little-endian hex word
        // Encoding reference: RISC-V ISA spec vol I, chapter 2
        $writememh("program.hex", uut.u_imem.mem);  // pre-clear

        // Hand-assemble the program:
        //  0: addi x1, x0, 5      → 00500093
        //  4: addi x2, x0, 3      → 00300113
        //  8: add  x3, x1, x2     → 002081B3
        // 12: sub  x4, x3, x2     → 40218233
        // 16: sw   x3, 0(x0)      → 00302023
        // 20: lw   x5, 0(x0)      → 00002283
        // 24: and  x6, x1, x2     → 0020F333
        // 28: or   x7, x1, x2     → 0020E3B3
        // 32: sll  x8, x1, x2     → 00209433
        // 36: slt  x9, x2, x1     → 001124B3
        // 40: beq  x6, x9, +8     → 00930463   (offset=+8 → skip 1 instr)
        // 44: addi x10,x0, 99     → 06300513   (should be skipped)
        // 48: addi x10,x0, 42     → 02A00513   (branch target)
        // 52: mac  x11,x1, x2     → 0020A05B   (custom-0: funct3=000,funct7=0)
        // 56: mac  x11,x3, x2     → 0021A05B   (accumulate: x11=15+8*3=39)
        // 60: nop                  → 00000013

        uut.u_imem.mem[0]  = 32'h00500093;
        uut.u_imem.mem[1]  = 32'h00300113;
        uut.u_imem.mem[2]  = 32'h002081B3;
        uut.u_imem.mem[3]  = 32'h40218233;
        uut.u_imem.mem[4]  = 32'h00302023;
        uut.u_imem.mem[5]  = 32'h00002283;
        uut.u_imem.mem[6]  = 32'h0020F333;
        uut.u_imem.mem[7]  = 32'h0020E3B3;
        uut.u_imem.mem[8]  = 32'h00209433;
        uut.u_imem.mem[9]  = 32'h001124B3;
        uut.u_imem.mem[10] = 32'h00930463;
        uut.u_imem.mem[11] = 32'h06300513;  // should be skipped
        uut.u_imem.mem[12] = 32'h02A00513;
        uut.u_imem.mem[13] = 32'h0020858B;  // MAC x11 = 0 + 5*3
        uut.u_imem.mem[14] = 32'h0021858B;  // MAC x11 = 15 + 8*3
        uut.u_imem.mem[15] = 32'h00000013;  // NOP

        // Fill rest with NOPs
        for (cycle = 16; cycle < 256; cycle = cycle + 1)
            uut.u_imem.mem[cycle] = 32'h00000013;

        // ── Reset ──────────────────────────────────────────
        @(posedge clk); #1;
        rst = 0;

        // ── Run enough cycles for the program ──────────────
        // 16 instructions × 1 cycle each = 16 cycles min
        // Give 20 to be safe
        repeat(20) @(posedge clk);
        #1;  // settle combinational outputs

        // ── Check results ──────────────────────────────────
        $display("\n=== Register file results ===");
        chk(`RF[1],  32'd5,   "x1  = 5  (addi)");
        chk(`RF[2],  32'd3,   "x2  = 3  (addi)");
        chk(`RF[3],  32'd8,   "x3  = 8  (add)");
        chk(`RF[4],  32'd5,   "x4  = 5  (sub)");
        chk(`RF[5],  32'd8,   "x5  = 8  (lw)");
        chk(`RF[6],  32'd1,   "x6  = 1  (and)");
        chk(`RF[7],  32'd7,   "x7  = 7  (or)");
        chk(`RF[8],  32'd40,  "x8  = 40 (sll)");
        chk(`RF[9],  32'd1,   "x9  = 1  (slt)");
        chk(`RF[10], 32'd42,  "x10 = 42 (branch taken, skip 99)");
        chk(`RF[11], 32'd39,  "x11 = 39 (MAC: 0+5*3=15, 15+8*3=39)");

        $display("\n=== Data memory ===");
        chk(`MEM[0], 32'd8,   "mem[0] = 8 (sw x3)");

        if (errors == 0)
            $display("\n=== ALL SINGLE-CYCLE TESTS PASSED ===");
        else
            $display("\n=== %0d FAILURE(S) ===", errors);

        $finish;
    end

endmodule