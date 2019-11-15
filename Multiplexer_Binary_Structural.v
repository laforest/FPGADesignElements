
//# A Reliable and Generic Binary Multiplexer (Structural Implementation)

// Takes in a concatenation of words (`words_in`) with the zeroth element on
// the right.  The binary selector then selects one of the input words. If the
// selector value is greater than the number of input words, the output will
// be the Boolean combination (given by `IMPLEMENTATION`) of an all-zero input
// (since no input word will be selected, so all are annulled).

// This structural implementation generalizes and makes portable the original
// [Behavioural Binary Multiplexer](./Multiplexer_Binary.html), and also
// avoids the same simulation/synthesis mismatch. Neither the [Binary to
// One-Hot Converter](./Binary_to_One_Hot.html) or the [One-Hot
// Multiplexer](./Multiplexer_One_Hot.html) use Verilog-specific constructs,
// and so should directly translate into other HDLs, and the output function
// is no longer limited to a Boolean OR word reduction, which allows some
// computation to be folded in.

`default_nettype none

module Multiplexer_Binary_Structural
#(
    parameter   WORD_WIDTH      = 0,
    parameter   ADDR_WIDTH      = 0,
    parameter   INPUT_COUNT     = 0,
    parameter   OPERATION       = "OR",
    parameter   IMPLEMENTATION  = "AND",

    // Do not set at instantiation
    parameter   TOTAL_WIDTH = WORD_WIDTH * INPUT_COUNT
)
(
    input   wire    [ADDR_WIDTH-1:0]    selector,
    input   wire    [TOTAL_WIDTH-1:0]   words_in,
    output  wire    [WORD_WIDTH-1:0]    word_out
);

// First, we convert the binary selector to a one-hot selector.

    wire [INPUT_COUNT-1:0] selector_one_hot;

    Binary_to_One_Hot
    #(
        .BINARY_WIDTH   (ADDR_WIDTH),
        .OUTPUT_WIDTH   (INPUT_COUNT) 
    )
    selector_converter
    (
        .binary_in      (selector),
        .one_hot_out    (selector_one_hot)
    );

// Then we use a One-Hot Multiplexer, which will annul the unselected input
// words then reduce them to the output word using the specified Boolean
// operation.

    Multiplexer_One_Hot
    #(
        .WORD_WIDTH     (WORD_WIDTH),
        .WORD_COUNT     (INPUT_COUNT),
        .OPERATION      (OPERATION),
        .IMPLEMENTATION (IMPLEMENTATION)
    )
    multiplexer_core
    (
        .selectors      (selector_one_hot),
        .words_in       (words_in),
        .word_out       (word_out)
    );

endmodule

