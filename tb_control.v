// ============================================================
// tb_control.v  —  Tests for main_decoder, alu_decoder, imm_gen
// Run: iverilog -o tb_ctrl tb_control.v control.v && vvp tb_ctrl
// ============================================================
`timescale 1ns/1ps

module tb_control;

    integer errors = 0;

    // ── main_decoder signals ───────────────────────────────
    reg  [6:0] opcode;
    wire       reg_write, alu_src, mem_write, mem_read;
    wire       mem_to_reg, branch, jump, jalr, lui_op, mac_op;
    wire [1:0] alu_op;

    main_decoder u_main (
        .opcode(opcode),
        .reg_write(reg_write), .alu_src(alu_src),
        .mem_write(mem_write), .mem_read(mem_read),
        .mem_to_reg(mem_to_reg), .branch(branch),
        .jump(jump), .jalr(jalr), .lui_op(lui_op),
        .mac_op(mac_op), .alu_op(alu_op)
    );

    // ── alu_decoder signals ────────────────────────────────
    reg  [1:0] ad_aluop;
    reg  [2:0] funct3;
    reg        funct7_5, opcode_5, ad_lui;
    wire [3:0] alu_ctrl;

    alu_decoder u_alu_dec (
        .alu_op(ad_aluop), .funct3(funct3),
        .funct7_5(funct7_5), .opcode_5(opcode_5),
        .lui_op(ad_lui), .alu_ctrl(alu_ctrl)
    );

    // ── imm_gen signals ────────────────────────────────────
    reg  [31:0] instr;
    wire [31:0] imm_ext;

    imm_gen u_imm (.instr(instr), .imm_ext(imm_ext));

    // ── helper tasks ───────────────────────────────────────
    task chk1;
        input got, exp;
        input [8*24:1] label;
        begin
            if (got !== exp) begin
                $display("FAIL  %-24s got=%b exp=%b", label, got, exp);
                errors = errors + 1;
            end else $display("PASS  %s", label);
        end
    endtask

    task chk2;
        input [1:0] got, exp;
        input [8*24:1] label;
        begin
            if (got !== exp) begin
                $display("FAIL  %-24s got=%02b exp=%02b", label, got, exp);
                errors = errors + 1;
            end else $display("PASS  %s", label);
        end
    endtask

    task chk4;
        input [3:0] got, exp;
        input [8*24:1] label;
        begin
            if (got !== exp) begin
                $display("FAIL  %-24s got=%04b exp=%04b", label, got, exp);
                errors = errors + 1;
            end else $display("PASS  %s", label);
        end
    endtask

    task chk32;
        input [31:0] got, exp;
        input [8*28:1] label;
        begin
            if (got !== exp) begin
                $display("FAIL  %-28s got=%08h exp=%08h", label, got, exp);
                errors = errors + 1;
            end else $display("PASS  %s", label);
        end
    endtask

    initial begin

        // ══════════════════════════════════════════════════
        // MAIN DECODER
        // ══════════════════════════════════════════════════
        $display("\n--- main_decoder: R-type (0110011) ---");
        opcode = 7'b0110011; #1;
        chk1(reg_write, 1, "R: reg_write=1");
        chk1(alu_src,   0, "R: alu_src=0");
        chk1(mem_write, 0, "R: mem_write=0");
        chk1(branch,    0, "R: branch=0");
        chk1(mac_op,    0, "R: mac_op=0");
        chk2(alu_op, 2'b10, "R: alu_op=10");

        $display("--- main_decoder: I-arith (0010011) ---");
        opcode = 7'b0010011; #1;
        chk1(reg_write, 1, "Iarith: reg_write=1");
        chk1(alu_src,   1, "Iarith: alu_src=1");
        chk2(alu_op, 2'b10, "Iarith: alu_op=10");

        $display("--- main_decoder: Load (0000011) ---");
        opcode = 7'b0000011; #1;
        chk1(reg_write,  1, "Load: reg_write=1");
        chk1(alu_src,    1, "Load: alu_src=1");
        chk1(mem_read,   1, "Load: mem_read=1");
        chk1(mem_to_reg, 1, "Load: mem_to_reg=1");
        chk2(alu_op, 2'b00,  "Load: alu_op=00");

        $display("--- main_decoder: Store (0100011) ---");
        opcode = 7'b0100011; #1;
        chk1(reg_write, 0, "Store: reg_write=0");
        chk1(mem_write, 1, "Store: mem_write=1");
        chk1(alu_src,   1, "Store: alu_src=1");

        $display("--- main_decoder: Branch (1100011) ---");
        opcode = 7'b1100011; #1;
        chk1(branch,    1, "Branch: branch=1");
        chk1(reg_write, 0, "Branch: reg_write=0");
        chk2(alu_op, 2'b01, "Branch: alu_op=01");

        $display("--- main_decoder: LUI (0110111) ---");
        opcode = 7'b0110111; #1;
        chk1(reg_write, 1, "LUI: reg_write=1");
        chk1(lui_op,    1, "LUI: lui_op=1");

        $display("--- main_decoder: JAL (1101111) ---");
        opcode = 7'b1101111; #1;
        chk1(jump,      1, "JAL: jump=1");
        chk1(reg_write, 1, "JAL: reg_write=1");

        $display("--- main_decoder: JALR (1100111) ---");
        opcode = 7'b1100111; #1;
        chk1(jump,      1, "JALR: jump=1");
        chk1(jalr,      1, "JALR: jalr=1");
        chk1(alu_src,   1, "JALR: alu_src=1");

        $display("--- main_decoder: MAC custom-0 (0001011) ---");
        opcode = 7'b0001011; #1;
        chk1(mac_op,    1, "MAC: mac_op=1");
        chk1(reg_write, 1, "MAC: reg_write=1");
        chk2(alu_op, 2'b11, "MAC: alu_op=11");

        // ══════════════════════════════════════════════════
        // ALU DECODER
        // ══════════════════════════════════════════════════
        $display("\n--- alu_decoder ---");
        ad_lui = 0;

        // alu_op=00 → ADD always
        ad_aluop = 2'b00; funct3 = 3'b000; funct7_5 = 0; opcode_5 = 0; #1;
        chk4(alu_ctrl, 4'b0000, "aluop=00 → ADD");

        // alu_op=01 → SUB always
        ad_aluop = 2'b01; #1;
        chk4(alu_ctrl, 4'b0001, "aluop=01 → SUB");

        // alu_op=11 → MUL (MAC)
        ad_aluop = 2'b11; #1;
        chk4(alu_ctrl, 4'b1010, "aluop=11 → MUL");

        // alu_op=10, funct3=000, R-type SUB (funct7_5=1, opcode_5=1)
        ad_aluop = 2'b10; funct3 = 3'b000; funct7_5 = 1; opcode_5 = 1; #1;
        chk4(alu_ctrl, 4'b0001, "R-type SUB");

        // alu_op=10, funct3=000, ADDI (funct7_5 irrelevant, opcode_5=0)
        ad_aluop = 2'b10; funct3 = 3'b000; funct7_5 = 1; opcode_5 = 0; #1;
        chk4(alu_ctrl, 4'b0000, "ADDI not SUB");

        // SLL
        ad_aluop = 2'b10; funct3 = 3'b001; funct7_5 = 0; opcode_5 = 1; #1;
        chk4(alu_ctrl, 4'b0101, "SLL");

        // SRL (funct7_5=0)
        ad_aluop = 2'b10; funct3 = 3'b101; funct7_5 = 0; opcode_5 = 1; #1;
        chk4(alu_ctrl, 4'b0110, "SRL");

        // SRA (funct7_5=1)
        ad_aluop = 2'b10; funct3 = 3'b101; funct7_5 = 1; opcode_5 = 1; #1;
        chk4(alu_ctrl, 4'b0111, "SRA");

        // AND / OR / XOR
        ad_aluop = 2'b10; funct3 = 3'b111; #1; chk4(alu_ctrl, 4'b0010, "AND");
        ad_aluop = 2'b10; funct3 = 3'b110; #1; chk4(alu_ctrl, 4'b0011, "OR");
        ad_aluop = 2'b10; funct3 = 3'b100; #1; chk4(alu_ctrl, 4'b0100, "XOR");

        // SLT / SLTU
        ad_aluop = 2'b10; funct3 = 3'b010; #1; chk4(alu_ctrl, 4'b1000, "SLT");
        ad_aluop = 2'b10; funct3 = 3'b011; #1; chk4(alu_ctrl, 4'b1001, "SLTU");

        // LUI passthrough
        ad_aluop = 2'b10; ad_lui = 1; funct3 = 3'b000; #1;
        chk4(alu_ctrl, 4'b1011, "LUI passthrough");
        ad_lui = 0;

        // ══════════════════════════════════════════════════
        // IMMEDIATE GENERATOR
        // ══════════════════════════════════════════════════
        $display("\n--- imm_gen ---");

        // ADDI x1, x0, -1   →  I-imm = 0xFFFFF800 sign-extended
        // instr[31:20] = 12'hFFF  (−1)
        // Encoding: imm[11:0]=FFF, rs1=00000, funct3=000, rd=00001, op=0010011
        instr = 32'hFFF00093; #1;  // addi x1, x0, -1
        chk32(imm_ext, 32'hFFFFFFFF, "I-type imm -1");

        // ADDI x1, x0, 5
        instr = 32'h00500093; #1;  // addi x1, x0, 5
        chk32(imm_ext, 32'h00000005, "I-type imm +5");

        // SW x2, 8(x1)  →  S-imm = 8  (imm[11:5]=0000000, imm[4:0]=01000)
        instr = 32'h00212423; #1;  // sw x2, 8(x1)
        chk32(imm_ext, 32'h00000008, "S-type imm +8");

        // BEQ x1, x2, +16  →  B-imm = 16 (offset, PC-relative)
        // B encoding: imm[12|10:5]=0001000, rs2=00010, rs1=00001, f3=000, imm[4:1|11]=0000, op=1100011
        instr = 32'h00208863; #1;  // beq x1, x2, +16
        chk32(imm_ext, 32'h00000010, "B-type imm +16");

        // LUI x3, 0x12345  →  U-imm = 0x12345000
        instr = 32'h123451B7; #1;  // lui x3, 0x12345
        chk32(imm_ext, 32'h12345000, "U-type LUI imm");

        // JAL x1, +8  →  J-imm = 8
        instr = 32'h008000EF; #1;  // jal x1, +8
        chk32(imm_ext, 32'h00000008, "J-type imm +8");

        // ══════════════════════════════════════════════════
        if (errors == 0)
            $display("\n=== ALL CONTROL TESTS PASSED ===");
        else
            $display("\n=== %0d FAILURE(S) ===", errors);

        $finish;
    end

endmodule