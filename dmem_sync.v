// ============================================================
// dmem_sync.v  —  Data memory for FPGAs whose block RAM needs a
//                 registered read address (Intel MAX 10 M9K)
//
// Behaves exactly like dmem.v. The MEM-stage address is the EX/MEM
// register's ALU result, which is loaded from the EX-stage result
// every cycle (EX/MEM is never stalled or flushed). This RAM keeps its
// own register (ra) loaded from that same EX-stage result, so
// ra == waddr[AW+1:2] every cycle and rd is the same word dmem.v reads.
//   write : byte-masked, at waddr (the MEM-stage address), on the edge
//   read  : mem[ra]
// This is Intel's "simple dual-port RAM with byte enables and a
// registered read address" template, which Quartus maps onto M9K.
// A store followed by a load of the same word reads the new data
// (Quartus adds pass-through logic for this if it needs to).
//
// Selected in Riscv_pipeline.v by `define FPGA_SYNC_MEM.
// ============================================================
module dmem_sync #(
    parameter AW = 8
) (
    input  wire        clk,
    input  wire        we,
    input  wire [3:0]  be,          // byte enables
    input  wire [31:0] waddr,       // MEM-stage byte address (EX/MEM result)
    input  wire [31:0] wd,          // lane-aligned write data
    input  wire [31:0] raddr_next,  // EX-stage result (next MEM address)
    output wire [31:0] rd
);
    reg [31:0]   mem [0:(1<<AW)-1];
    reg [AW-1:0] ra;

    always @(posedge clk) begin
        if (we) begin
            if (be[0]) mem[waddr[AW+1:2]][7:0]   <= wd[7:0];
            if (be[1]) mem[waddr[AW+1:2]][15:8]  <= wd[15:8];
            if (be[2]) mem[waddr[AW+1:2]][23:16] <= wd[23:16];
            if (be[3]) mem[waddr[AW+1:2]][31:24] <= wd[31:24];
        end
        ra <= raddr_next[AW+1:2];
    end

    assign rd = mem[ra];
endmodule
