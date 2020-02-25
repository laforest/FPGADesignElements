
//# Number of Leading Zeros

// Takes in a binary number and returns an unsigned binary number of the same
// width containing the count of zeros from the most-significant bit down to
// the first 1 bit (leading zeros), or the width of the word if all-zero. 
// For example:

// * 11111 --> 00000 (0)
// * 11000 --> 00000 (0)
// * 10000 --> 00000 (0)
// * 01100 --> 00001 (1)
// * 00010 --> 00011 (3)
// * 00000 --> 00101 (5)

// We can trivially implement this at no extra hardware cost by wiring the
// input number backwards (bit-reversed) into a [Number of Trailing
// Zeros](./Number_of_Trailing_Zeros.html) function.
// Bit-reversing the input word converts the leftmost bit of interest into
// the rightmost bit of interest, enabling us to use the right-to-left bit
// parallelism of Extended Boolean Operations (specifically: [isolating the
// rightmost 1 bit](./Bitmask_Isolate_Rightmost_1_Bit.html)).

`default_nettype none

module Number_of_Leading_Zeros
#(
    parameter WORD_WIDTH = 0
)
(
    input   wire    [WORD_WIDTH-1:0]    word_in,
    output  wire    [WORD_WIDTH-1:0]    word_out
);

    wire [WORD_WIDTH-1:0] word_in_reversed;

    Word_Reverser
    #(
        .WORD_WIDTH (1),
        .WORD_COUNT (WORD_WIDTH)
    )
    bit_reverse
    (
        .words_in   (word_in),
        .words_out  (word_in_reversed)
    );

    Number_of_Trailing_Zeros
    #(
        .WORD_WIDTH (WORD_WIDTH)
    )
    calc_ntz
    (
        .word_in    (word_in_reversed),
        .word_out   (word_out)
    );

endmodule

