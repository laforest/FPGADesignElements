
//# Bitmask: Thermometer from Count

// Credit: [Hacker's Delight](./reading.html#Warren2013), Section 2-1: Manipulating Rightmost Bits

// Sets the first N least-significant bits given integer N.
// If N is greater than WORD_WIDTH, then the mask is all-ones.

// This thermometer bitmask is also the lexicographically first member of the
// set of bitmasks with a given number of set bits (that is, with a constant
// population count). The last member is the same sequence, but with the bit
// order reversed (see: [Word Reverser](./Word_Reverser.html)). To generate
// all members, use [Bitmask: Next with Constant
// Popcount](./Bitmask_Next_with_Constant_Popcount.html).

`default_nettype none

module Bitmask_Thermometer_from_Count
#(
    parameter WORD_WIDTH    = 0
)
(
    input   wire    [WORD_WIDTH-1:0]    count_in,
    output  reg     [WORD_WIDTH-1:0]    word_out
);

    localparam ONE = {{WORD_WIDTH-1{1'b0}},1'b1};

    initial begin
        word_out = {WORD_WIDTH{1'b0}};
    end

    always @(*) begin
        word_out = (ONE << count_in) - ONE;
    end

endmodule

