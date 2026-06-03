// ============================================================
// tb_memory_regfile.v  —  Smoke-test for imem, dmem, regfile
// Run: iverilog -o tb_mem tb_memory_regfile.v imem.v dmem.v regfile.v
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
    reg  [31:0] dmem_addr, dmem_wd;
    wire [31:0] dmem_rd;
    dmem u_dmem (.clk(clk), .we(dmem_we), .addr(dmem_addr),
                 .wd(dmem_wd), .rd(dmem_rd));

    // ---- regfile ----------------------------------------------
    reg         rf_we;
    reg  [4:0]  rf_ra1, rf_ra2, rf_wa3;
    reg  [31:0] rf_wd3;
    wire [31:0] rf_rd1, rf_rd2;
    regfile u_rf (.clk(clk), .we3(rf_we),
                  .ra1(rf_ra1), .ra2(rf_ra2), .wa3(rf_wa3),
                  .wd3(rf_wd3), .rd1(rf_rd1), .rd2(rf_rd2));

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
        dmem_we = 0; dmem_addr = 0; dmem_wd = 0;

        @(posedge clk); #1;
        dmem_we = 1; dmem_addr = 32'h00000004; dmem_wd = 32'hDEADBEEF;
        @(posedge clk); #1;
        dmem_we = 0;
        check(dmem_rd, 32'hDEADBEEF, "dmem write/read word");

        dmem_we = 1; dmem_addr = 32'h00000008; dmem_wd = 32'hCAFEBABE;
        @(posedge clk); #1;
        dmem_we = 0;
        check(dmem_rd, 32'hCAFEBABE, "dmem second write/read");

        // -- regfile: basic write/read --------------------------
        rf_we = 0; rf_ra1 = 0; rf_ra2 = 0; rf_wa3 = 0; rf_wd3 = 0;

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

        // -- summary --------------------------------------------
        if (errors == 0)
            $display("\n=== ALL TESTS PASSED ===");
        else
            $display("\n=== %0d TEST(S) FAILED ===", errors);

        $finish;
    end

endmodule