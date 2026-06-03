// ============================================================
// dmem.v  —  Data Memory (Read / Write)
// 256 words × 32-bit = 1 KB
// Synchronous write (on posedge clk), async read
// Supports word (SW/LW) access only for now —
// byte/half-word extensions added later with mem_size signal
// ============================================================
module dmem (
    input  wire        clk,
    input  wire        we,         // write enable (1 = write)
    input  wire [31:0] addr,       // byte address
    input  wire [31:0] wd,         // write data
    output wire [31:0] rd          // read data
);

    reg [31:0] mem [0:255];

    // Synchronous write
    always @(posedge clk) begin
        if (we)
            mem[addr[9:2]] <= wd;
    end

    // Asynchronous read
    assign rd = mem[addr[9:2]];

endmodule