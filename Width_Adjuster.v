
//# Width Adjuster

// Takes in a vector of a given input width, a flag denoting if it is
// a signed/unsigned value, and an output width. Outputs the same vector
// extended or truncated to the output width, with signed/unsigned extension.
// **There is no guard against truncating so much you lose significant bits.**

// You would use this to normalize binary integers to the same *constant*
// width before doing arithmetic or Boolean operations upon them.  The [max
// function](./max_function.html) is handy for this when you don't know the
// widths ahead of time (e.g.: when they depend on another module parameter).

`default_nettype none

module Width_Adjuster
#(
    parameter WORD_WIDTH_IN     = 0,
    parameter SIGNED            = 0,
    parameter WORD_WIDTH_OUT    = 0
)
(
    // It's possible some input bits are truncated away
    // verilator lint_off UNUSED
    input   wire    [WORD_WIDTH_IN-1:0]     original_input,
    // verilator lint_on  UNUSED
    output  reg     [WORD_WIDTH_OUT-1:0]    adjusted_output
);

// Calculate the width difference and handle each possible case:

// * Zero: we wire the input to the output
// * Larger: we sign-extend the input with a pad
// * Smaller: we truncate the input

    localparam PAD_WIDTH = WORD_WIDTH_OUT - WORD_WIDTH_IN;

    generate
        if (PAD_WIDTH == 0) begin: zero
            always @(*) begin
                adjusted_output = original_input;
            end
        end

        if (PAD_WIDTH > 0) begin: sign_extend
            localparam PAD_ZERO = {PAD_WIDTH{1'b0}};
            localparam PAD_ONES = {PAD_WIDTH{1'b1}};
            always @(*) begin
                adjusted_output = ((SIGNED != 0) && (original_input[WORD_WIDTH_IN-1] == 1'b1)) ? {PAD_ONES, original_input} : {PAD_ZERO, original_input};
            end
        end

        if (PAD_WIDTH < 0) begin: truncate
            always @(*) begin
                adjusted_output = original_input [WORD_WIDTH_OUT-1:0];
            end
        end
    endgenerate

endmodule

