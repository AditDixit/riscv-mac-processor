// ============================================================
// mul_pipe.v  —  Two-stage 32×32 → low-32 multiplier
//
// Stage 1 (EX):  three 16×16 partial products, registered.
//                Each maps onto one FPGA DSP block (MULT18X18D on ECP5).
// Stage 2 (MEM): prod = ll + ((lh + hl) << 16), mod 2^32.
//                (a_hi × b_hi only affects bits 32 and up, so it is
//                 not needed for the low 32 bits that MUL/MAC keep.)
//
// The registers capture every cycle, in step with the EX/MEM pipeline
// register (which is never stalled or flushed), so `prod` belongs to
// the instruction currently in MEM.
// ============================================================
module mul_pipe (
    input  wire        clk,
    input  wire [31:0] a,         // operands from EX (after forwarding)
    input  wire [31:0] b,
    output wire [31:0] prod       // low 32 bits of a*b, one cycle later
);
    reg [31:0] p_ll;              // a[15:0]  * b[15:0]
    reg [15:0] p_lh, p_hl;        // low halves of the cross products

    wire [31:0] lh_full = a[15:0]  * b[31:16];
    wire [31:0] hl_full = a[31:16] * b[15:0];

    always @(posedge clk) begin
        p_ll <= a[15:0] * b[15:0];
        p_lh <= lh_full[15:0];
        p_hl <= hl_full[15:0];
    end

    assign prod = p_ll + {p_lh + p_hl, 16'b0};
endmodule
