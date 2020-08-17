
//# Turn On Trailing 0 Bits

// Credit: [Hacker's Delight](./reading.html#Warren2013), Section 2-1: Manipulating Rightmost Bits

// Use the following formula to turn on the trailing 0’s in a word, producing
// the original input if none (e.g., 10101000 -> 10101111)

`default_nettype none

module Turn_On_Trailing_0_Bits
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
        word_out = word_in | (word_in - ONE);
    end

endmodule

