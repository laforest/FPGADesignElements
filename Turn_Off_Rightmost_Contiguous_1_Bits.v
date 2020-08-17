
//# Turn Off Rightmost Contiguous 1 Bits

// Credit: [Hacker's Delight](./reading.html#Warren2013), Section 2-1: Manipulating Rightmost Bits

// Use  the following formula to turn off the rightmost contiguous 
// string of 1’s (e.g., 01011100 -> 01000000)

// It can be used to determine if a nonnegative integer is of the form 2^j-2^k
// for some j >= k >= 0: apply the formula followed by a 0-test on the result.

`default_nettype none

module Turn_Off_Rightmost_Contiguous_1_Bits
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
        word_out = ((word_in & (-word_in)) + word_in) & word_in; 
    end

endmodule

