
//# Bitmask: Isolate Rightmost 1 Bit

// Credit: [Hacker's Delight](./books.html#Warren2013), Section 2-1: Manipulating Rightmost Bits

// Use the following formula to isolate the rightmost 1-bit, producing 0 if
// none (e.g., 01011000 -> 00001000)

// This function can trivially implement a [Priority
// Arbiter](./Priority_Arbiter.html), with the highest priority given to the
// least-significant bit.

`default_nettype none

module Bitmask_Isolate_Rightmost_1_Bit
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

    always @(*) begin
        word_out = word_in & (-word_in);
    end

endmodule

