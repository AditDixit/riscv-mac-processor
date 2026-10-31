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
    integer n_stall, n_ctrl, n_fwd_ex, n_fwd_mem, n_mac_byp;

    // Does the instruction now in EX really read rs1 / rs2? (The forwarding
    // unit compares register numbers regardless of format; these filter out
    // fields that are really immediates, so forwarding counts are exact.)
    reg [6:0] ex_opc;
    always @(posedge clk) if (uut.flush_id_ex || rst) ex_opc <= 7'h13; else ex_opc <= uut.id_opcode;
    wire uses_rs1 = !(ex_opc == 7'h37 || ex_opc == 7'h17 || ex_opc == 7'h6F || ex_opc == 7'h0F) && uut.ex_rs1 != 0;
    wire uses_rs2 = (ex_opc == 7'h33 || ex_opc == 7'h23 || ex_opc == 7'h63 || ex_opc == 7'h0B) && uut.ex_rs2 != 0;

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
        cycles = 0; n_stall = 0; n_ctrl = 0; n_fwd_ex = 0; n_fwd_mem = 0; n_mac_byp = 0;
        while (!(uut.ex_jump && uut.ex_pc === halt_pc) && cycles < 3000000) begin
            // Sample the instruction in EX during this cycle (performance counters)
            if (uut.stall_pc)                         n_stall   = n_stall + 1;
            if (uut.branch_taken_ex || uut.ex_jump)   n_ctrl    = n_ctrl + 1;
            if (uses_rs1 && uut.fwd_a == 2'b10)       n_fwd_ex  = n_fwd_ex + 1;
            if (uses_rs2 && uut.fwd_b == 2'b10)       n_fwd_ex  = n_fwd_ex + 1;
            if (uses_rs1 && uut.fwd_a == 2'b01)       n_fwd_mem = n_fwd_mem + 1;
            if (uses_rs2 && uut.fwd_b == 2'b01)       n_fwd_mem = n_fwd_mem + 1;
            if (uut.ex_mac_op && uut.ex_rd != 0 &&
                ((uut.mem_reg_write && uut.mem_rd == uut.ex_rd) ||
                 (uut.wb_reg_write  && uut.wb_rd  == uut.ex_rd))) n_mac_byp = n_mac_byp + 1;
            @(posedge clk); cycles = cycles + 1;
        end
        repeat (8) @(posedge clk);
        fd = $fopen(out_f, "w");
        for (i = 0; i < 32; i = i + 1) $fdisplay(fd, "%08x", uut.u_rf.rf[i]);
        for (i = 0; i < 256; i = i + 1) $fdisplay(fd, "%08x", uut.u_dmem.mem[i]);
        $fclose(fd);
        $display("CYCLES %0d", cycles);
        $display("STATS stall=%0d ctrl=%0d fwd_ex=%0d fwd_mem=%0d mac_bypass=%0d",
                 n_stall, n_ctrl, n_fwd_ex, n_fwd_mem, n_mac_byp);
        $finish;
    end
endmodule
