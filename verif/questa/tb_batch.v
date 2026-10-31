`timescale 1ns/1ps
// ============================================================
// tb_batch.v — runs many programs on the pipeline in ONE simulation
//
// Made for simulators where each launch is slow (Questa/ModelSim): the
// vectors come from verif/questa/gen_vectors.py, which assembles the
// programs and computes the expected final state with the reference
// simulator (verif/rvtools.py), so no Python is needed while simulating.
//
// +VEC=<file>  vector file of hex words, whitespace separated:
//                N, then per program:
//                halt_pc, instructions (reference count),
//                256 program words, 256 initial data words,
//                32 expected registers, 256 expected data words
// +OUT=<file>  one result line per program:
//                index cycles instrs loaduse muluse ctrl fwd_ex fwd_mem mac_fwd mismatches
//
// Per program: memories and registers are loaded, reset is held for 3
// cycles, the core runs until the halt instruction (jal x0, 0) reaches
// EX, drains 8 cycles, and all 32 registers and 256 data words are
// compared with the reference. The performance counters must satisfy
//   cycles = instrs + 3 + loaduse + muluse + 2*ctrl
// (the same identity as verif/perf.py); a program that breaks it is
// counted as an identity failure.
// ============================================================
module tb_batch;
    reg clk = 0, rst = 1;
    always #5 clk = ~clk;
    wire [31:0] pc_out;
    riscv_pipeline uut (.clk(clk), .rst(rst), .pc_out(pc_out));

    reg [1023:0] vec_f, out_f;
    integer fd, fo, rc, n, p, i, cycles, mism, bad_progs, bad_ident, total_cycles, total_instr;
    integer n_stall, n_mul_stall, n_ctrl, n_fwd_ex, n_fwd_mem, n_mac_byp;
    reg [31:0] w, halt_pc, instrs;
    reg [31:0] exp_regs [0:31];
    reg [31:0] exp_mem  [0:255];

    // Does the instruction now in EX really read rs1 / rs2? (filters out
    // immediate bits in the rs fields, so forwarding counts are exact)
    reg [6:0] ex_opc;
    always @(posedge clk) if (uut.flush_id_ex || rst) ex_opc <= 7'h13; else ex_opc <= uut.id_opcode;
    wire uses_rs1 = !(ex_opc == 7'h37 || ex_opc == 7'h17 || ex_opc == 7'h6F || ex_opc == 7'h0F) && uut.ex_rs1 != 0;
    wire uses_rs2 = (ex_opc == 7'h33 || ex_opc == 7'h23 || ex_opc == 7'h63 || ex_opc == 7'h0B) && uut.ex_rs2 != 0;

    task next_word;   // read one hex word from the vector file
        begin
            rc = $fscanf(fd, "%h", w);
            if (rc != 1) begin $display("ERROR: vector file ended early"); $finish; end
        end
    endtask

    initial begin
        if (!$value$plusargs("VEC=%s", vec_f)) begin $display("ERROR: +VEC missing"); $finish; end
        if (!$value$plusargs("OUT=%s", out_f)) begin $display("ERROR: +OUT missing"); $finish; end
        fd = $fopen(vec_f, "r");
        if (fd == 0) begin $display("ERROR: cannot open vector file"); $finish; end
        fo = $fopen(out_f, "w");
        next_word; n = w;
        bad_progs = 0; bad_ident = 0; total_cycles = 0; total_instr = 0;

        for (p = 0; p < n; p = p + 1) begin
            // ── load one program ─────────────────────────────
            rst = 1;
            next_word; halt_pc = w;
            next_word; instrs  = w;
            for (i = 0; i < 256; i = i + 1) begin next_word; uut.u_imem.mem[i] = w; end
            for (i = 0; i < 256; i = i + 1) begin next_word; uut.u_dmem.mem[i] = w; end
            for (i = 0; i < 32;  i = i + 1) begin next_word; exp_regs[i] = w; end
            for (i = 0; i < 256; i = i + 1) begin next_word; exp_mem[i]  = w; end
            for (i = 0; i < 32;  i = i + 1) uut.u_rf.rf[i] = 32'b0;

            // ── reset, run to the halt, drain ────────────────
            repeat (3) @(posedge clk);
            #1 rst = 0;
            cycles = 0; n_stall = 0; n_mul_stall = 0; n_ctrl = 0;
            n_fwd_ex = 0; n_fwd_mem = 0; n_mac_byp = 0;
            while (!(uut.ex_jump && uut.ex_pc === halt_pc) && cycles < 200000) begin
                if (uut.stall_pc && !uut.ex_mul)          n_stall     = n_stall + 1;
                if (uut.stall_pc &&  uut.ex_mul)          n_mul_stall = n_mul_stall + 1;
                if (uut.branch_taken_ex || uut.ex_jump)   n_ctrl      = n_ctrl + 1;
                if (uses_rs1 && uut.fwd_a == 2'b10)       n_fwd_ex    = n_fwd_ex + 1;
                if (uses_rs2 && uut.fwd_b == 2'b10)       n_fwd_ex    = n_fwd_ex + 1;
                if (uses_rs1 && uut.fwd_a == 2'b01)       n_fwd_mem   = n_fwd_mem + 1;
                if (uses_rs2 && uut.fwd_b == 2'b01)       n_fwd_mem   = n_fwd_mem + 1;
                if (uut.mem_mac_op && uut.mem_rd != 0 && uut.wb_reg_write && uut.wb_rd == uut.mem_rd)
                                                          n_mac_byp   = n_mac_byp + 1;
                @(posedge clk); cycles = cycles + 1;
            end
            repeat (8) @(posedge clk);

            // ── compare with the reference ───────────────────
            mism = 0;
            for (i = 0; i < 32;  i = i + 1) if (uut.u_rf.rf[i]    !== exp_regs[i]) mism = mism + 1;
            for (i = 0; i < 256; i = i + 1) if (uut.u_dmem.mem[i] !== exp_mem[i])  mism = mism + 1;
            if (mism != 0 || cycles >= 200000) bad_progs = bad_progs + 1;
            if (cycles != instrs + 3 + n_stall + n_mul_stall + 2 * n_ctrl) bad_ident = bad_ident + 1;
            total_cycles = total_cycles + cycles;
            total_instr  = total_instr + instrs;
            $fdisplay(fo, "%0d %0d %0d %0d %0d %0d %0d %0d %0d %0d", p, cycles, instrs,
                      n_stall, n_mul_stall, n_ctrl, n_fwd_ex, n_fwd_mem, n_mac_byp, mism);
        end
        $fclose(fo);
        $fclose(fd);
        $display("BATCH programs=%0d failing=%0d identity_failures=%0d instrs=%0d cycles=%0d",
                 n, bad_progs, bad_ident, total_instr, total_cycles);
        $finish;
    end
endmodule
