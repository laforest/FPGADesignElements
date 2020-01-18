
//# Hamming Distance

// Returns the number of bits which are different between two words.  Returns
// a WORD_WIDTH integer, which will get optimized down to using only the
// floor(log<sub>2</sub>(N))+1 least-significant bits.

`default_nettype none

module Hamming_Distance
#(
    parameter WORD_WIDTH    = 0
)
(
    input   wire    [WORD_WIDTH-1:0]    word_A,
    input   wire    [WORD_WIDTH-1:0]    word_B,
    output  wire    [WORD_WIDTH-1:0]    distance
);

    wire [WORD_WIDTH-1:0] different_bits;

    Word_Reducer
    #(
        .OPERATION  ("XOR"),
        .WORD_WIDTH (WORD_WIDTH),
        .WORD_COUNT (2)
    )
    compare_bits
    (
        .words_in   ({word_A, word_B}),
        .word_out   (different_bits)
    );

    Population_Count
    #(
        .WORD_WIDTH (WORD_WIDTH)
    )
    calc_hamming_dist
    (
        .word_in    (different_bits),
        .count_out  (distance)
    );

endmodule

