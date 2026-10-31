// ============================================================
// Tb_memory_regfile.v  —  Smoke-test for imem, dmem, lsu_align, regfile
// Run: iverilog -o tb_mem Tb_memory_regfile.v Imem.v dmem.v lsu_align.v RegFile.v
//      vvp tb_mem
// ============================================================
`timescale 1ns/1ps

module tb_memory_regfile;

    // ---- clock ------------------------------------------------
    reg clk = 0;
    always #5 clk = ~clk;   // 100 MHz

    // ---- imem -------------------------------------------------
    // imem needs a program.hex — we create a tiny one inline
    reg  [31:0] pc;
    wire [31:0] instr;
    imem u_imem (.addr(pc), .instr(instr));

    // ---- dmem -------------------------------------------------
    reg         dmem_we;
    reg  [3:0]  dmem_be;
    reg  [31:0] dmem_addr, dmem_wd;
    wire [31:0] dmem_rd;
    dmem u_dmem (.clk(clk), .we(dmem_we), .be(dmem_be), .addr(dmem_addr),
                 .wd(dmem_wd), .rd(dmem_rd));

    // ---- lsu_align (byte-lane steering) -----------------------
    reg  [2:0]  lsu_f3;
    reg  [1:0]  lsu_off;
    reg  [31:0] lsu_st, lsu_word;
    wire [31:0] lsu_sd, lsu_ld;
    wire [3:0]  lsu_be;
    lsu_align u_lsu (.funct3(lsu_f3), .addr_lo(lsu_off), .store_in(lsu_st),
                     .load_word(lsu_word), .store_data(lsu_sd),
                     .byte_en(lsu_be), .load_data(lsu_ld));

    // ---- regfile ----------------------------------------------
    reg         rf_we;
    reg  [4:0]  rf_ra1, rf_ra2, rf_ra_acc, rf_wa3;
    reg  [31:0] rf_wd3;
    wire [31:0] rf_rd1, rf_rd2, rf_rd_acc;
    regfile u_rf (.clk(clk), .we3(rf_we),
                  .ra1(rf_ra1), .ra2(rf_ra2), .ra_acc(rf_ra_acc), .wa3(rf_wa3),
                  .wd3(rf_wd3), .rd1(rf_rd1), .rd2(rf_rd2), .rd_acc(rf_rd_acc));

    // ---- test body --------------------------------------------
    integer errors = 0;

    task check;
        input [63:0] got;
        input [63:0] expected;
        input [127:0] label;
        begin
            if (got !== expected) begin
                $display("FAIL  %s : got %0h  expected %0h", label, got, expected);
                errors = errors + 1;
            end else
                $display("PASS  %s", label);
        end
    endtask

    initial begin
        // -- dmem: write then read ------------------------------
        dmem_we = 0; dmem_be = 4'b1111; dmem_addr = 0; dmem_wd = 0;

        @(posedge clk); #1;
        dmem_we = 1; dmem_addr = 32'h00000004; dmem_wd = 32'hDEADBEEF;
        @(posedge clk); #1;
        dmem_we = 0;
        check(dmem_rd, 32'hDEADBEEF, "dmem write/read word");

        dmem_we = 1; dmem_addr = 32'h00000008; dmem_wd = 32'hCAFEBABE;
        @(posedge clk); #1;
        dmem_we = 0;
        check(dmem_rd, 32'hCAFEBABE, "dmem second write/read");

        // -- dmem byte enables: only enabled lanes change --------
        dmem_we = 1; dmem_addr = 32'h00000004; dmem_wd = 32'h0000AB00; dmem_be = 4'b0010;
        @(posedge clk); #1;
        dmem_we = 0;
        check(dmem_rd, 32'hDEADABEF, "dmem byte lane 1");
        dmem_we = 1; dmem_wd = 32'h12340000; dmem_be = 4'b1100;
        @(posedge clk); #1;
        dmem_we = 0; dmem_be = 4'b1111;
        check(dmem_rd, 32'h1234ABEF, "dmem upper half");

        // -- lsu_align: load extension -------------------------
        lsu_word = 32'h80FF7F01; lsu_st = 32'h12345678;
        lsu_f3 = 3'b000; lsu_off = 2'd3; #1; check(lsu_ld, 32'hFFFFFF80, "lb sign-extend");
        lsu_f3 = 3'b100; lsu_off = 2'd3; #1; check(lsu_ld, 32'h00000080, "lbu zero-extend");
        lsu_f3 = 3'b000; lsu_off = 2'd0; #1; check(lsu_ld, 32'h00000001, "lb byte 0");
        lsu_f3 = 3'b000; lsu_off = 2'd1; #1; check(lsu_ld, 32'h0000007F, "lb byte 1");
        lsu_f3 = 3'b001; lsu_off = 2'd2; #1; check(lsu_ld, 32'hFFFF80FF, "lh sign-extend");
        lsu_f3 = 3'b101; lsu_off = 2'd2; #1; check(lsu_ld, 32'h000080FF, "lhu zero-extend");
        lsu_f3 = 3'b001; lsu_off = 2'd0; #1; check(lsu_ld, 32'h00007F01, "lh low half");
        lsu_f3 = 3'b010; lsu_off = 2'd0; #1; check(lsu_ld, 32'h80FF7F01, "lw full word");

        // -- lsu_align: store lanes and byte enables ------------
        lsu_f3 = 3'b000; lsu_off = 2'd2; #1;
        check({lsu_sd, 28'b0, lsu_be}, {32'h78787878, 32'h4}, "sb lanes, be");
        lsu_f3 = 3'b001; lsu_off = 2'd2; #1;
        check({lsu_sd, 28'b0, lsu_be}, {32'h56785678, 32'hC}, "sh lanes, be");
        lsu_f3 = 3'b001; lsu_off = 2'd0; #1;
        check({lsu_sd, 28'b0, lsu_be}, {32'h56785678, 32'h3}, "sh low, be");
        lsu_f3 = 3'b010; lsu_off = 2'd0; #1;
        check({lsu_sd, 28'b0, lsu_be}, {32'h12345678, 32'hF}, "sw lanes, be");

        // -- regfile: basic write/read --------------------------
        rf_we = 0; rf_ra1 = 0; rf_ra2 = 0; rf_ra_acc = 0; rf_wa3 = 0; rf_wd3 = 0;

        // Write 0x12345678 to x5
        @(posedge clk); #1;
        rf_we = 1; rf_wa3 = 5'd5; rf_wd3 = 32'h12345678;
        @(posedge clk); #1;
        rf_we = 0;
        rf_ra1 = 5'd5;
        #1;
        check(rf_rd1, 32'h12345678, "regfile write x5 / read x5");

        // Write to x1 and x2, read both simultaneously
        rf_we = 1; rf_wa3 = 5'd1; rf_wd3 = 32'hAAAAAAAA;
        @(posedge clk); #1;
        rf_wa3 = 5'd2; rf_wd3 = 32'h55555555;
        @(posedge clk); #1;
        rf_we = 0;
        rf_ra1 = 5'd1; rf_ra2 = 5'd2;
        #1;
        check(rf_rd1, 32'hAAAAAAAA, "regfile read x1");
        check(rf_rd2, 32'h55555555, "regfile read x2");

        // x0 must always read as zero
        rf_we = 1; rf_wa3 = 5'd0; rf_wd3 = 32'hFFFFFFFF;
        @(posedge clk); #1;
        rf_we = 0;
        rf_ra1 = 5'd0;
        #1;
        check(rf_rd1, 32'h0, "regfile x0 hardwired zero");

        // Write-through bypass: read same register being written
        rf_we = 1; rf_wa3 = 5'd7; rf_wd3 = 32'hBEEFCAFE;
        rf_ra1 = 5'd7;
        #1;
        check(rf_rd1, 32'hBEEFCAFE, "regfile write-through bypass");
        @(posedge clk); #1;
        rf_we = 0;

        // Accumulator read port (used by MAC): plain read, x0, write-through
        rf_ra_acc = 5'd5;
        #1;
        check(rf_rd_acc, 32'h12345678, "regfile acc port read x5");
        rf_ra_acc = 5'd0;
        #1;
        check(rf_rd_acc, 32'h0, "regfile acc port x0 = zero");
        rf_we = 1; rf_wa3 = 5'd9; rf_wd3 = 32'h0BADF00D;
        rf_ra_acc = 5'd9;
        #1;
        check(rf_rd_acc, 32'h0BADF00D, "regfile acc port write-through");
        @(posedge clk); #1;
        rf_we = 0;

        // -- summary --------------------------------------------
        if (errors == 0)
            $display("\n=== ALL TESTS PASSED ===");
        else
            $display("\n=== %0d TEST(S) FAILED ===", errors);

        $finish;
    end

endmodule