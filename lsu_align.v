// ============================================================
// lsu_align.v  —  Byte-lane steering for sub-word loads/stores
//
// Pure combinational. Sits beside the data memory:
//   stores: replicates rs2 into the right byte lanes and produces
//           a 4-bit byte-enable (SB / SH / SW)
//   loads : picks the addressed byte/halfword out of the 32-bit
//           memory word and sign- or zero-extends it
//           (LB / LH / LW / LBU / LHU)
//
// funct3 is the load/store instruction's funct3 field:
//   000 B   001 H   010 W   100 BU   101 HU
//
// Alignment: accesses are assumed naturally aligned. A misaligned
// halfword or word access is not trapped; the low address bits that
// would make it misaligned are ignored (halfword uses addr[1],
// word ignores addr[1:0]). The reference simulator in verif/ models
// exactly this behaviour.
// ============================================================
module lsu_align (
    input  wire [2:0]  funct3,
    input  wire [1:0]  addr_lo,        // byte offset within the word
    input  wire [31:0] store_in,       // rs2 value
    input  wire [31:0] load_word,      // 32-bit word read from memory
    output reg  [31:0] store_data,     // lane-replicated write data
    output reg  [3:0]  byte_en,        // write byte enables
    output reg  [31:0] load_data       // extended load result
);
    wire [7:0]  ld_byte = load_word >> {addr_lo, 3'b000};
    wire [15:0] ld_half = addr_lo[1] ? load_word[31:16] : load_word[15:0];

    always @(*) begin
        case (funct3[1:0])
            2'b00: begin                                   // SB
                store_data = {4{store_in[7:0]}};
                byte_en    = 4'b0001 << addr_lo;
            end
            2'b01: begin                                   // SH
                store_data = {2{store_in[15:0]}};
                byte_en    = addr_lo[1] ? 4'b1100 : 4'b0011;
            end
            default: begin                                 // SW
                store_data = store_in;
                byte_en    = 4'b1111;
            end
        endcase

        case (funct3)
            3'b000:  load_data = {{24{ld_byte[7]}},  ld_byte};   // LB
            3'b001:  load_data = {{16{ld_half[15]}}, ld_half};   // LH
            3'b100:  load_data = {24'b0, ld_byte};               // LBU
            3'b101:  load_data = {16'b0, ld_half};               // LHU
            default: load_data = load_word;                      // LW
        endcase
    end
endmodule
