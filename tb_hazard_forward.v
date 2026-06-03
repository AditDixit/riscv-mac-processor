// ============================================================
// tb_hazard_forward.v
// Run: iverilog -o tb_hf tb_hazard_forward.v
//               hazard_unit.v forward_unit.v && vvp tb_hf
// ============================================================
`timescale 1ns/1ps

module tb_hazard_forward;

    integer errors = 0;

    // ── hazard_unit ports ─────────────────────────────────
    reg        id_ex_mem_read;
    reg [4:0]  id_ex_rd_h, if_id_rs1_h, if_id_rs2_h;
    reg        branch_taken, jump_sig;
    wire       stall, flush_if_id, flush_id_ex;

    hazard_unit u_haz (
        .id_ex_mem_read(id_ex_mem_read),
        .id_ex_rd(id_ex_rd_h),
        .if_id_rs1(if_id_rs1_h),
        .if_id_rs2(if_id_rs2_h),
        .branch_taken(branch_taken),
        .jump(jump_sig),
        .stall(stall),
        .flush_if_id(flush_if_id),
        .flush_id_ex(flush_id_ex)
    );

    // ── forward_unit ports ────────────────────────────────
    reg [4:0]  id_ex_rs1, id_ex_rs2;
    reg [4:0]  ex_mem_rd, mem_wb_rd;
    reg        ex_mem_rw, mem_wb_rw;
    wire [1:0] fwd_a, fwd_b;

    forward_unit u_fwd (
        .id_ex_rs1(id_ex_rs1),
        .id_ex_rs2(id_ex_rs2),
        .ex_mem_rd(ex_mem_rd),
        .ex_mem_reg_write(ex_mem_rw),
        .mem_wb_rd(mem_wb_rd),
        .mem_wb_reg_write(mem_wb_rw),
        .forward_a(fwd_a),
        .forward_b(fwd_b)
    );

    task chk1;
        input got, exp;
        input [8*40:1] label;
        begin
            if (got !== exp) begin
                $display("FAIL  %-40s got=%b exp=%b", label, got, exp);
                errors = errors + 1;
            end else $display("PASS  %s", label);
        end
    endtask

    task chk2;
        input [1:0] got, exp;
        input [8*40:1] label;
        begin
            if (got !== exp) begin
                $display("FAIL  %-40s got=%02b exp=%02b", label, got, exp);
                errors = errors + 1;
            end else $display("PASS  %s", label);
        end
    endtask

    initial begin

        // ══════════════════════════════════════════════════
        // HAZARD UNIT TESTS
        // ══════════════════════════════════════════════════
        $display("--- Hazard Unit: no hazard ---");
        id_ex_mem_read=0; id_ex_rd_h=5'd3;
        if_id_rs1_h=5'd1; if_id_rs2_h=5'd2;
        branch_taken=0; jump_sig=0; #1;
        chk1(stall,       0, "no hazard: stall=0");
        chk1(flush_if_id, 0, "no hazard: flush_if_id=0");
        chk1(flush_id_ex, 0, "no hazard: flush_id_ex=0");

        $display("--- Hazard Unit: load-use on rs1 ---");
        id_ex_mem_read=1; id_ex_rd_h=5'd5;
        if_id_rs1_h=5'd5; if_id_rs2_h=5'd2; #1;
        chk1(stall,       1, "load-use rs1: stall=1");
        chk1(flush_id_ex, 1, "load-use rs1: flush_id_ex=1");
        chk1(flush_if_id, 0, "load-use rs1: flush_if_id=0");

        $display("--- Hazard Unit: load-use on rs2 ---");
        id_ex_mem_read=1; id_ex_rd_h=5'd7;
        if_id_rs1_h=5'd1; if_id_rs2_h=5'd7; #1;
        chk1(stall,       1, "load-use rs2: stall=1");
        chk1(flush_id_ex, 1, "load-use rs2: flush_id_ex=1");

        $display("--- Hazard Unit: load-use rd=x0 (no stall) ---");
        id_ex_mem_read=1; id_ex_rd_h=5'd0;
        if_id_rs1_h=5'd0; if_id_rs2_h=5'd0; #1;
        chk1(stall, 0, "load-use x0: no stall");

        $display("--- Hazard Unit: load but different rd ---");
        id_ex_mem_read=1; id_ex_rd_h=5'd4;
        if_id_rs1_h=5'd1; if_id_rs2_h=5'd2; #1;
        chk1(stall, 0, "load diff rd: no stall");

        $display("--- Hazard Unit: branch taken ---");
        id_ex_mem_read=0; branch_taken=1; jump_sig=0;
        if_id_rs1_h=5'd1; if_id_rs2_h=5'd2; #1;
        chk1(flush_if_id, 1, "branch taken: flush_if_id=1");
        chk1(flush_id_ex, 1, "branch taken: flush_id_ex=1");
        chk1(stall,       0, "branch taken: stall=0");

        $display("--- Hazard Unit: jump ---");
        branch_taken=0; jump_sig=1; #1;
        chk1(flush_if_id, 1, "jump: flush_if_id=1");
        chk1(flush_id_ex, 1, "jump: flush_id_ex=1");
        chk1(stall,       0, "jump: stall=0");
        branch_taken=0; jump_sig=0;

        // ══════════════════════════════════════════════════
        // FORWARDING UNIT TESTS
        // ══════════════════════════════════════════════════
        $display("--- Forward Unit: no hazard ---");
        id_ex_rs1=5'd1; id_ex_rs2=5'd2;
        ex_mem_rd=5'd5; ex_mem_rw=1;
        mem_wb_rd=5'd6; mem_wb_rw=1; #1;
        chk2(fwd_a, 2'b00, "no match: fwd_a=00");
        chk2(fwd_b, 2'b00, "no match: fwd_b=00");

        $display("--- Forward Unit: EX-EX forward on A ---");
        id_ex_rs1=5'd5; id_ex_rs2=5'd2;
        ex_mem_rd=5'd5; ex_mem_rw=1;
        mem_wb_rd=5'd5; mem_wb_rw=1; #1;
        chk2(fwd_a, 2'b10, "EX-EX fwd_a=10 (priority over MEM-EX)");
        chk2(fwd_b, 2'b00, "EX-EX fwd_b=00 (rs2 no match)");

        $display("--- Forward Unit: MEM-EX forward on A ---");
        id_ex_rs1=5'd6; id_ex_rs2=5'd2;
        ex_mem_rd=5'd5; ex_mem_rw=1;
        mem_wb_rd=5'd6; mem_wb_rw=1; #1;
        chk2(fwd_a, 2'b01, "MEM-EX fwd_a=01");

        $display("--- Forward Unit: EX-EX forward on B ---");
        id_ex_rs1=5'd1; id_ex_rs2=5'd5;
        ex_mem_rd=5'd5; ex_mem_rw=1;
        mem_wb_rd=5'd6; mem_wb_rw=1; #1;
        chk2(fwd_a, 2'b00, "EX-EX fwd_a=00");
        chk2(fwd_b, 2'b10, "EX-EX fwd_b=10");

        $display("--- Forward Unit: MEM-EX forward on B ---");
        id_ex_rs1=5'd1; id_ex_rs2=5'd6;
        ex_mem_rd=5'd5; ex_mem_rw=1;
        mem_wb_rd=5'd6; mem_wb_rw=1; #1;
        chk2(fwd_b, 2'b01, "MEM-EX fwd_b=01");

        $display("--- Forward Unit: both A and B forwarded ---");
        id_ex_rs1=5'd5; id_ex_rs2=5'd6;
        ex_mem_rd=5'd5; ex_mem_rw=1;
        mem_wb_rd=5'd6; mem_wb_rw=1; #1;
        chk2(fwd_a, 2'b10, "both: fwd_a=10 (EX-EX)");
        chk2(fwd_b, 2'b01, "both: fwd_b=01 (MEM-EX)");

        $display("--- Forward Unit: reg_write=0 disables forward ---");
        id_ex_rs1=5'd5; id_ex_rs2=5'd6;
        ex_mem_rd=5'd5; ex_mem_rw=0;   // write disabled
        mem_wb_rd=5'd6; mem_wb_rw=0;   // write disabled
        #1;
        chk2(fwd_a, 2'b00, "rw=0: fwd_a=00");
        chk2(fwd_b, 2'b00, "rw=0: fwd_b=00");

        $display("--- Forward Unit: x0 never forwarded ---");
        id_ex_rs1=5'd0; id_ex_rs2=5'd0;
        ex_mem_rd=5'd0; ex_mem_rw=1;
        mem_wb_rd=5'd0; mem_wb_rw=1; #1;
        chk2(fwd_a, 2'b00, "x0: fwd_a=00");
        chk2(fwd_b, 2'b00, "x0: fwd_b=00");

        // ══════════════════════════════════════════════════
        if (errors == 0)
            $display("\n=== ALL HAZARD/FORWARD TESTS PASSED ===");
        else
            $display("\n=== %0d FAILURE(S) ===", errors);

        $finish;
    end

endmodule