`timescale 1ns/1ps
// ============================================================
// tb_arch.v — runs one riscv-arch-test program on the pipeline
//
// +PROG=<hex>   test image ($readmemh format, word addresses; may use
//               @address lines to skip zero runs), loaded into BOTH
//               instruction and data memory
// +HALT=<addr>  byte address of the rvmodel_halt self-loop
// +SIGB=<addr> +SIGE=<addr>  signature region [begin, end)
// +OUT=<file>   optional: signature words written here, one per line
// +REF=<file>   optional: reference signature (one word per line);
//               the testbench compares and prints
//               ARCH-RESULT words=<n> mismatches=<m>
//
// Memories are 2^19 words (2 MB) each so the largest test (jal-01,
// which exercises far jumps) fits. They are cleared before loading.
// ============================================================
module tb_arch;
    reg clk = 0, rst = 1;
    always #5 clk = ~clk;
    wire [31:0] pc_out;
    riscv_pipeline #(.MEM_AW(19)) uut (.clk(clk), .rst(rst), .pc_out(pc_out));

    reg [1023:0] prog_f, out_f, ref_f;
    integer halt_pc, sigb, sige, cycles, a, fd, have_out, have_ref, words, mism;
    reg [31:0] refm [0:4095];

    initial begin
        if (!$value$plusargs("PROG=%s", prog_f) || !$value$plusargs("HALT=%d", halt_pc) ||
            !$value$plusargs("SIGB=%d", sigb)    || !$value$plusargs("SIGE=%d", sige)) begin
            $display("ERROR: missing plusarg"); $finish;
        end
        have_out = $value$plusargs("OUT=%s", out_f);
        have_ref = $value$plusargs("REF=%s", ref_f);
        for (a = 0; a < (1 << 19); a = a + 1) begin
            uut.u_imem.mem[a] = 32'b0;
            uut.u_dmem.mem[a] = 32'b0;
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
        if (have_out) begin
            fd = $fopen(out_f, "w");
            for (a = sigb; a < sige; a = a + 4) $fdisplay(fd, "%08x", uut.u_dmem.mem[a >> 2]);
            $fclose(fd);
        end
        if (have_ref) begin
            $readmemh(ref_f, refm);
            words = (sige - sigb) / 4;
            mism = 0;
            for (a = 0; a < words; a = a + 1)
                if (uut.u_dmem.mem[(sigb >> 2) + a] !== refm[a]) mism = mism + 1;
            $display("ARCH-RESULT words=%0d mismatches=%0d", words, mism);
        end
        $display("CYCLES %0d", cycles);
        $finish;
    end
endmodule
