
//# Bitwise 2:1 Multiplexer

// Selects each bit from one of two input words, based on a bitmask of the
// same width. For each bitmask bit, 0 selects the corresponding bit from
// word_in_0, and 1 selects from word_in_1.

// This function may look trivial, but it implements the important and useful
// Shannon Decomposition, originally known as Boole's Expansion Theorem, which
// allows you to compose smaller Boolean functions of N variables into
// a larger one of N+1 variables.

`default_nettype none

module Multiplexer_Bitwise_2to1
#(
    parameter WORD_WIDTH = 0
)
(
    input   wire    [WORD_WIDTH-1:0]    bitmask,
    input   wire    [WORD_WIDTH-1:0]    word_in_0,
    input   wire    [WORD_WIDTH-1:0]    word_in_1,
    output  wire    [WORD_WIDTH-1:0]    word_out
);

    generate
        genvar j;
        for(j = 0; j < WORD_WIDTH; j = j+1) begin: per_bit
            Multiplexer_Binary_Behavioural
            #(
                .WORD_WIDTH     (1),
                .ADDR_WIDTH     (1),
                .INPUT_COUNT    (2)
            )
            bitwise
            (
                .selector       (bitmask[j]),    
                .words_in       ({word_in_1[j],word_in_0[j]}),
                .word_out       (word_out[j])
            );
        end
    endgenerate

endmodule

