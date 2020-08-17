
//# Bitmask: Turn On Trailing 0 Bits

// Credit: [Hacker's Delight](./reading.html#Warren2013), Section 2-1: Manipulating Rightmost Bits

// Use one of the following formulas to create a word with 1’s at the
// positions of the trailing 0’s in the input, and 0’s elsewhere, producing
// 0 if none (e.g., 01011000 -> 00000111)

`default_nettype none

module Bitmask_Turn_On_Trailing_0_Bits
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
        word_out = ~word_in & (word_in - ONE);
    end

endmodule

