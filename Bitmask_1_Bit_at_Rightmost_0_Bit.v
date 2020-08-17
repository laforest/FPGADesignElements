
//# Bitmask: 1 Bit at Rightmost 0 Bit

// Credit: [Hacker's Delight](./reading.html#Warren2013), Section 2-1: Manipulating Rightmost Bits

// Use the following formula to create a word with a single 1-bit at the
// position of the rightmost 0-bit in the input, producing 0 if none (e.g.,
// 10100111 -> 00001000)

`default_nettype none

module Bitmask_1_Bit_at_Rightmost_0_Bit
#(
    parameter WORD_WIDTH = 0
)
(
    input   wire    [WORD_WIDTH-1:0]    word_in,
    output  reg     [WORD_WIDTH-1:0]    word_out
);

    initial begin
        word_out = {WORD_WIDTH{1'b0}};
    end

    localparam ONE = {{WORD_WIDTH-1{1'b0}},1'b1};

    always @(*) begin
        word_out = ~word_in & (word_in + ONE);
    end

endmodule

