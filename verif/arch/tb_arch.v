`timescale 1ns/1ps
// ============================================================
// tb_arch.v — runs one riscv-arch-test program on the pipeline
//
// +PROG=<hex>   test image (one 32-bit word per line, from address 0),
//               loaded into BOTH instruction and data memory
// +HALT=<addr>  byte address of the rvmodel_halt self-loop
// +SIGB=<addr> +SIGE=<addr>  signature region [begin, end)
// +OUT=<file>   signature words written here, one per line
//
// Memories are 2^19 words (2 MB) each so the largest test (jal-01,
// which exercises far jumps) fits.
// ============================================================
module tb_arch;
    reg clk = 0, rst = 1;
    always #5 clk = ~clk;
    wire [31:0] pc_out;
    riscv_pipeline #(.MEM_AW(19)) uut (.clk(clk), .rst(rst), .pc_out(pc_out));

    reg [1023:0] prog_f, out_f;
    integer halt_pc, sigb, sige, cycles, a, fd;

    initial begin
        if (!$value$plusargs("PROG=%s", prog_f) || !$value$plusargs("HALT=%d", halt_pc) ||
            !$value$plusargs("SIGB=%d", sigb)    || !$value$plusargs("SIGE=%d", sige) ||
            !$value$plusargs("OUT=%s", out_f)) begin
            $display("ERROR: missing plusarg"); $finish;
        end
        $readmemh(prog_f, uut.u_imem.mem);
        $readmemh(prog_f, uut.u_dmem.mem);
        repeat (3) @(posedge clk);
        #1 rst = 0;
        cycles = 0;
        while (!(uut.ex_jump && uut.ex_pc === halt_pc) && cycles < 5000000) begin
            @(posedge clk); cycles = cycles + 1;
        end
        repeat (8) @(posedge clk);
        if (cycles >= 5000000) $display("TIMEOUT");
        fd = $fopen(out_f, "w");
        for (a = sigb; a < sige; a = a + 4) $fdisplay(fd, "%08x", uut.u_dmem.mem[a >> 2]);
        $fclose(fd);
        $display("CYCLES %0d", cycles);
        $finish;
    end
endmodule
