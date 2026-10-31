// ============================================================
// imem_sync.v  —  Instruction memory for FPGAs whose block RAM
//                 needs a registered read address (Intel MAX 10 M9K)
//
// Behaves exactly like imem.v. imem.v reads mem[pc_if] combinationally;
// here the RAM keeps its own copy of the PC's word address in a register
// (ra), loaded from the NEXT PC on the same edge that loads pc_if:
//   reset      -> 0           (pc_if resets to 0)
//   !stall     -> next_addr   (pc_if <= pc_next)
//   stall      -> hold        (pc_if holds)
// so ra == pc_if[AW+1:2] every cycle, and instr is the same word.
// This is Intel's "RAM with registered read address" template, which
// Quartus maps onto M9K block RAM.
//
// Selected in Riscv_pipeline.v by `define FPGA_SYNC_MEM.
// ============================================================
module imem_sync #(
    parameter AW = 8                  // word-address bits: 2^AW words
) (
    input  wire          clk,
    input  wire          rst,
    input  wire          en,          // = !stall: PC advances this cycle
    input  wire [31:0]   next_addr,   // pc_next (byte address)
    input  wire          we,          // program-load port (FPGA builds)
    input  wire [AW-1:0] waddr,
    input  wire [31:0]   wdata,
    output wire [31:0]   instr
);
    reg [31:0]   mem [0:(1<<AW)-1];
    reg [AW-1:0] ra;

    always @(posedge clk) begin
        if (we) mem[waddr] <= wdata;
        if (rst | en) ra <= rst ? {AW{1'b0}} : next_addr[AW+1:2];
    end

    assign instr = mem[ra];
endmodule
