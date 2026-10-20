`timescale 1ns/1ps
// ============================================================
// Testbench : program runner for differential tests and benchmarks
//
// Loads +PROG=<hex> into instruction memory and optional +DATA=<hex> into
// data memory, runs until the halt instruction (jal x0,0 at +HALT=<byte addr>)
// is executing in the EX stage (a wrong-path fetch of that address after a
// taken branch is squashed and does not count), drains the pipeline, then writes the architectural state to
// +OUT=<file> (x0..x31, then 256 data words, one hex word per line) and
// prints "CYCLES <n>", the number of clock cycles from reset release until
// the halt instruction reached EX.
// ============================================================
module tb_prog_runner;
    reg clk = 0, rst = 1;
    always #5 clk = ~clk;
    wire [31:0] pc_out;
    riscv_pipeline uut (.clk(clk), .rst(rst), .pc_out(pc_out));

    reg [1023:0] prog_f, data_f, out_f;
    integer halt_pc, cycles, i, fd, have_data, have_halt;

    initial begin
        if (!$value$plusargs("PROG=%s", prog_f)) begin $display("ERROR: +PROG missing"); $finish; end
        $readmemh(prog_f, uut.u_imem.mem);
        have_data = $value$plusargs("DATA=%s", data_f);
        if (have_data) $readmemh(data_f, uut.u_dmem.mem);
        have_halt = $value$plusargs("HALT=%d", halt_pc);
        if (!have_halt) begin $display("ERROR: +HALT missing"); $finish; end
        if (!$value$plusargs("OUT=%s", out_f)) begin $display("ERROR: +OUT missing"); $finish; end
        repeat (3) @(posedge clk);
        #1 rst = 0;
        cycles = 0;
        while (!(uut.ex_jump && uut.ex_pc === halt_pc) && cycles < 3000000) begin
            @(posedge clk); cycles = cycles + 1;
        end
        repeat (8) @(posedge clk);
        fd = $fopen(out_f, "w");
        for (i = 0; i < 32; i = i + 1) $fdisplay(fd, "%08x", uut.u_rf.rf[i]);
        for (i = 0; i < 256; i = i + 1) $fdisplay(fd, "%08x", uut.u_dmem.mem[i]);
        $fclose(fd);
        $display("CYCLES %0d", cycles);
        $finish;
    end
endmodule
