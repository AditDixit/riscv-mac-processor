// ============================================================
// tb_alu.v  —  Exhaustive test for alu.v
// Run: iverilog -o tb_alu tb_alu.v alu.v && vvp tb_alu
// ============================================================
`timescale 1ns/1ps

module tb_alu;

    reg  [31:0] src_a, src_b;
    reg  [3:0]  alu_ctrl;
    wire [31:0] result;
    wire        zero, negative, overflow;

    alu uut (
        .src_a(src_a), .src_b(src_b), .alu_ctrl(alu_ctrl),
        .result(result), .zero(zero), .negative(negative),
        .overflow(overflow)
    );

    integer errors = 0;

    task check32;
        input [31:0] got, expected;
        input [8*30:1] label;
        begin
            if (got !== expected) begin
                $display("FAIL  %-30s got=%08h  exp=%08h", label, got, expected);
                errors = errors + 1;
            end else
                $display("PASS  %s", label);
        end
    endtask

    task check1;
        input got, expected;
        input [8*30:1] label;
        begin
            if (got !== expected) begin
                $display("FAIL  %-30s got=%b  exp=%b", label, got, expected);
                errors = errors + 1;
            end else
                $display("PASS  %s", label);
        end
    endtask

    initial begin
        $display("--- ADD ---");
        alu_ctrl = 4'b0000;
        src_a = 32'd15;       src_b = 32'd10;
        #1; check32(result, 32'd25,         "ADD  15+10=25");
        src_a = 32'hFFFFFFFF; src_b = 32'd1;
        #1; check32(result, 32'd0,           "ADD  wrap-around");
        check1(zero, 1'b1,                   "ADD  zero flag");

        $display("--- SUB ---");
        alu_ctrl = 4'b0001;
        src_a = 32'd20;       src_b = 32'd7;
        #1; check32(result, 32'd13,          "SUB  20-7=13");
        src_a = 32'd5;        src_b = 32'd10;
        #1; check32(result, 32'hFFFFFFFB,    "SUB  underflow wraps");
        check1(negative, 1'b1,               "SUB  negative flag");

        $display("--- AND / OR / XOR ---");
        alu_ctrl = 4'b0010;
        src_a = 32'hFF00FF00; src_b = 32'h0F0F0F0F;
        #1; check32(result, 32'h0F000F00,    "AND");
        alu_ctrl = 4'b0011;
        #1; check32(result, 32'hFF0FFF0F,    "OR");
        alu_ctrl = 4'b0100;
        #1; check32(result, 32'hF00FF00F,    "XOR");

        $display("--- Shifts ---");
        alu_ctrl = 4'b0101;
        src_a = 32'h00000001; src_b = 32'd4;
        #1; check32(result, 32'h00000010,    "SLL 1<<4");

        alu_ctrl = 4'b0110;
        src_a = 32'h80000000; src_b = 32'd1;
        #1; check32(result, 32'h40000000,    "SRL MSB>>1 logical");

        alu_ctrl = 4'b0111;
        src_a = 32'h80000000; src_b = 32'd1;
        #1; check32(result, 32'hC0000000,    "SRA MSB>>1 arithmetic");

        $display("--- SLT / SLTU ---");
        alu_ctrl = 4'b1000;
        src_a = 32'hFFFFFFFF; src_b = 32'd1;   // -1 < 1 signed
        #1; check32(result, 32'd1,              "SLT -1 < 1 (signed)");
        src_a = 32'd5;        src_b = 32'd5;
        #1; check32(result, 32'd0,              "SLT 5 < 5 = false");

        alu_ctrl = 4'b1001;
        src_a = 32'hFFFFFFFF; src_b = 32'd1;   // big unsigned > 1
        #1; check32(result, 32'd0,              "SLTU 0xFFFFFFFF < 1 = false");
        src_a = 32'd1;        src_b = 32'hFFFFFFFF;
        #1; check32(result, 32'd1,              "SLTU 1 < 0xFFFFFFFF = true");

        $display("--- MUL (MAC operand) ---");
        alu_ctrl = 4'b1010;
        src_a = 32'd7;        src_b = 32'd6;
        #1; check32(result, 32'd42,             "MUL 7*6=42");
        src_a = 32'h00010001; src_b = 32'h00010001;
        #1; check32(result, 32'h00020001,       "MUL partial products");
        src_a = 32'hFFFFFFFF; src_b = 32'd2;
        #1; check32(result, 32'hFFFFFFFE,       "MUL low32 of -1*2");

        $display("--- LUI passthrough ---");
        alu_ctrl = 4'b1011;
        src_a = 32'hDEAD_0000; src_b = 32'hBEEF_0000;
        #1; check32(result, 32'hBEEF_0000,      "LUI passes src_b");

        $display("--- Overflow flag ---");
        alu_ctrl = 4'b0000;
        src_a = 32'h7FFFFFFF; src_b = 32'd1;   // max positive + 1
        #1; check1(overflow, 1'b1,              "ADD overflow: maxpos+1");
        src_a = 32'd1;        src_b = 32'd1;
        #1; check1(overflow, 1'b0,              "ADD no overflow: 1+1");

        $display("--- Zero flag ---");
        alu_ctrl = 4'b0001;
        src_a = 32'd42; src_b = 32'd42;
        #1; check1(zero, 1'b1,                  "SUB zero flag: 42-42");

        // -------------------------------------------------------
        if (errors == 0)
            $display("\n=== ALL ALU TESTS PASSED ===");
        else
            $display("\n=== %0d FAILURE(S) ===", errors);

        $finish;
    end

endmodule