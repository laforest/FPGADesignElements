
//# Turn Off Rightmost 1 Bit

// Credit: [Hacker's Delight](./reading.html#Warren2013), Section 2-1: Manipulating Rightmost Bits

//Use the following formula to turn off the rightmost 1-bit in a word,
//producing 0 if none (e.g., 01011000 -> 01010000)

//This can be used to determine if an unsigned integer is a power of 2 or is
//0: apply the formula followed by a 0-test on the result.

`default_nettype none

module Turn_Off_Rightmost_1_Bit
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
        word_out = word_in & (word_in - ONE);
    end

endmodule

