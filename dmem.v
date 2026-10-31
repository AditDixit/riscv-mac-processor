// ============================================================
// dmem.v  —  Data Memory (Read / Write)
// 2^AW words × 32-bit (default 256 words = 1 KB)
// Synchronous write (on posedge clk) with per-byte write enables,
// asynchronous word read. Byte/halfword selection and extension
// on loads is done outside the memory, in lsu_align.v.
// ============================================================
module dmem #(
    parameter AW = 8               // word-address bits: 2^AW words (8 → 1 KB)
) (
    input  wire        clk,
    input  wire        we,         // write enable (1 = write)
    input  wire [3:0]  be,         // byte enables (bit i = byte lane i)
    input  wire [31:0] addr,       // byte address
    input  wire [31:0] wd,         // write data (already lane-aligned)
    output wire [31:0] rd          // read data (full word)
);

    reg [31:0] mem [0:(1<<AW)-1];

    // Synchronous byte-masked write
    always @(posedge clk) begin
        if (we) begin
            if (be[0]) mem[addr[AW+1:2]][7:0]   <= wd[7:0];
            if (be[1]) mem[addr[AW+1:2]][15:8]  <= wd[15:8];
            if (be[2]) mem[addr[AW+1:2]][23:16] <= wd[23:16];
            if (be[3]) mem[addr[AW+1:2]][31:24] <= wd[31:24];
        end
    end

    // Asynchronous read
    assign rd = mem[addr[AW+1:2]];

endmodule
