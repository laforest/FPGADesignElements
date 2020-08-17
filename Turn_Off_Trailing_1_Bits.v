
//# Turn Off Trailing 1 Bits

// Credit: [Hacker's Delight](./reading.html#Warren2013), Section 2-1: Manipulating Rightmost Bits

// Use the following formula to turn off the trailing 1’s in a word, producing
// the original input if none (e.g., 10100111 -> 10100000)

// This can be used to determine if an unsigned integer is of the form
// (2^n)-1, 0, or all 1’s: apply the formula followed by a 0-test on the
// result.

`default_nettype none

module Turn_Off_Trailing_1_Bits
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
        word_out = word_in & (word_in + ONE);
    end

endmodule

