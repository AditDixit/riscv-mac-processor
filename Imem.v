// ============================================================
// imem.v  —  Instruction Memory
// 2^AW words × 32-bit (default 256 words = 1 KB)
// Word-addressed: addr[AW+1:2] selects the word (byte addr >> 2)
// Combinational (async) read — result available same cycle
//
// FPGA builds define FPGA_PROG_PORT, which adds a synchronous
// program-load write port (as a bootloader would use). Without it the
// synthesis tool sees a ROM with no contents and removes the core.
// Simulation builds leave it undefined and load program.hex instead.
// ============================================================
module imem #(
    parameter AW = 8              // word-address bits: 2^AW words (8 → 1 KB)
) (
`ifdef FPGA_PROG_PORT
    input  wire        clk,
    input  wire        we,        // program-load write enable
    input  wire [AW-1:0] waddr,   // word address
    input  wire [31:0] wdata,
`endif
    input  wire [31:0] addr,      // byte address from PC
    output wire [31:0] instr      // 32-bit instruction out
);

    reg [31:0] mem [0:(1<<AW)-1]; // 2^AW × 32-bit words

`ifdef FPGA_PROG_PORT
    always @(posedge clk)
        if (we) mem[waddr] <= wdata;
`else
    // Initialise from hex file during simulation.
    // Replace "program.hex" with your assembled program.
    initial begin
        $readmemh("program.hex", mem);
    end
`endif

    // Word-aligned read: drop the 2 LSBs
    assign instr = mem[addr[AW+1:2]];

endmodule
