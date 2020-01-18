
//# Bitmask: Turn Off Trailing 1 Bits

// Credit: [Hacker's Delight](./books.html#Warren2013), Section 2-1: Manipulating Rightmost Bits

// Use the following formula to create a word with 0’s at the positions of the
// trailing 1’s in the input, and 1’s elsewhere, producing all 1’s if none
// (e.g., 10100111 -> 11111000)

`default_nettype none

module Bitmask_Turn_Off_Trailing_1_Bits
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
        word_out = ~word_in | (word_in + ONE);
    end

endmodule

