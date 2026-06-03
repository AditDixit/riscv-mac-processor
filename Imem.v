// ============================================================
// imem.v  —  Instruction Memory (Read-Only)
// 256 words × 32-bit = 1 KB
// Word-addressed: addr[9:2] selects the word (byte addr >> 2)
// Combinational (async) read — result available same cycle
// ============================================================
module imem (
    input  wire [31:0] addr,      // byte address from PC
    output wire [31:0] instr      // 32-bit instruction out
);

    reg [31:0] mem [0:255];       // 256 × 32-bit words

    // Initialise from hex file during simulation.
    // Replace "program.hex" with your assembled program.
    initial begin
        $readmemh("program.hex", mem);
    end

    // Word-aligned read: drop the 2 LSBs
    assign instr = mem[addr[9:2]];

endmodule