// ============================================================
// regfile.v  —  32 × 32-bit Register File
//
// Ports:
//   Two async read ports  (ra1/ra2 → rd1/rd2)
//   One synchronous write port (wa3/wd3, enabled by we3)
//
// x0 is hardwired to zero — writes to x0 are silently ignored.
//
// Read-after-write in the same cycle:
//   If ra1/ra2 == wa3 AND we3 is high, the NEW value is
//   forwarded immediately (transparent / bypassing read).
//   This matches the behaviour expected by the WB→ID path
//   in a pipelined design that writes on the first half of
//   the clock and reads on the second half.
// ============================================================
module regfile (
    input  wire        clk,
    input  wire        we3,        // write enable
    input  wire [4:0]  ra1,        // read address 1
    input  wire [4:0]  ra2,        // read address 2
    input  wire [4:0]  wa3,        // write address
    input  wire [31:0] wd3,        // write data
    output wire [31:0] rd1,        // read data 1
    output wire [31:0] rd2         // read data 2
);

    reg [31:0] rf [0:31];

    // Initialise all registers to 0 (good practice for simulation)
    integer i;
    initial begin
        for (i = 0; i < 32; i = i + 1)
            rf[i] = 32'b0;
    end

    // Synchronous write — x0 stays zero
    always @(posedge clk) begin
        if (we3 && wa3 != 5'b0)
            rf[wa3] <= wd3;
    end

    // Asynchronous read with write-through bypass for x0 safety
    assign rd1 = (ra1 == 5'b0)              ? 32'b0 :
                 (we3 && ra1 == wa3)        ? wd3   :
                 rf[ra1];

    assign rd2 = (ra2 == 5'b0)              ? 32'b0 :
                 (we3 && ra2 == wa3)        ? wd3   :
                 rf[ra2];

endmodule