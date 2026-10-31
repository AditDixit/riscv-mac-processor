// ============================================================
// dmem.v  —  Data Memory (Read / Write)
// 256 words × 32-bit = 1 KB
// Synchronous write (on posedge clk) with per-byte write enables,
// asynchronous word read. Byte/halfword selection and extension
// on loads is done outside the memory, in lsu_align.v.
// ============================================================
module dmem (
    input  wire        clk,
    input  wire        we,         // write enable (1 = write)
    input  wire [3:0]  be,         // byte enables (bit i = byte lane i)
    input  wire [31:0] addr,       // byte address
    input  wire [31:0] wd,         // write data (already lane-aligned)
    output wire [31:0] rd          // read data (full word)
);

    reg [31:0] mem [0:255];

    // Synchronous byte-masked write
    always @(posedge clk) begin
        if (we) begin
            if (be[0]) mem[addr[9:2]][7:0]   <= wd[7:0];
            if (be[1]) mem[addr[9:2]][15:8]  <= wd[15:8];
            if (be[2]) mem[addr[9:2]][23:16] <= wd[23:16];
            if (be[3]) mem[addr[9:2]][31:24] <= wd[31:24];
        end
    end

    // Asynchronous read
    assign rd = mem[addr[9:2]];

endmodule
