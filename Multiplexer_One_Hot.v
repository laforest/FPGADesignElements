
//# Multiplexer (One-Hot)

// Takes in a one-hot bit vector (`selector`), and outputs the value of the
// corresponding input. All selectors and inputs are concatenated into
// a single vector each.

// If more than one `selector` bit is set, the output is a Boolean combination
// of the selected input words, as specified by `OPERATION`: OR for a plain
// multiplexer, AND to show each bit where all the words agree, NOR to show each
// bit which are not set in all the words, etc...

// The `IMPLEMENTATION` parameter defaults to "AND" since this is all Boolean
// logic, though if you are feeding the input words from registers all sharing
// common control logic, you might get a possibly better result by selecting
// "MUX". If it matters for speed or area, use the implementation which ends
// up using the register's reset/clear pin, which will remove the Annuller
// logic from the multiplexer itself.

`default_nettype none

module Multiplexer_One_Hot
#(
    parameter       WORD_WIDTH          = 32,
    parameter       WORD_COUNT          = 5,
    parameter       OPERATION           = "OR",
    parameter       IMPLEMENTATION      = "AND",

    // Do not set at instantiation
    parameter   TOTAL_WIDTH = WORD_COUNT * WORD_WIDTH
)
(
    input   wire    [WORD_COUNT-1:0]    selectors,
    input   wire    [TOTAL_WIDTH-1:0]   words_in,
    output  wire    [WORD_WIDTH-1:0]    word_out
);

// First, create a copy of `words_in`, but with non-selected words annulled.

    wire [TOTAL_WIDTH-1:0] words_in_selected;

    generate

        genvar i;

        for (i=0; i < WORD_COUNT; i=i+1) begin : per_word

            Annuller
            #(
                .WORD_WIDTH     (WORD_WIDTH),
                .IMPLEMENTATION (IMPLEMENTATION)
            )
            select_input
            (
                .annul       (selectors[i] == 1'b0),
                .data_in     (words_in          [WORD_WIDTH*i +: WORD_WIDTH]),
                .data_out    (words_in_selected [WORD_WIDTH*i +: WORD_WIDTH])
            );

        end

    endgenerate

// Then reduce the filtered words to one word, maybe getting a final useful
// computation done in the process, depending on the selected `OPERATION`.

    Word_Reducer
    #(
        .OPERATION  (OPERATION),
        .WORD_WIDTH (WORD_WIDTH),
        .WORD_COUNT (WORD_COUNT)
    )
    combine_words
    (
        .words_in   (words_in_selected),
        .word_out   (word_out)
    );

endmodule

