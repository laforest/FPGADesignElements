
//# Word Reverser

// Reverses the order of words in the input vector, composed of concatenated
// words, with the first word at the right.  We can't reverse vectors via
// reversed indices in Verilog, so we must use a for loop to manually move the
// bits around.

// The `WORD_WIDTH` and `WORD_COUNT` parameters express how the input vector
// is split-up, and so defines which reversal happens. The total width is
// always the product of the word width and count. For example:

// * `WORD_WIDTH = 1` and `WORD_COUNT = 32` reverses all the bits in a 32-bit word.
// * `WORD_WIDTH = 8` and `WORD_COUNT = 4` reverses the endianness of bytes in a 32-bit word.

// There is no clock or Boolean logic, and everything is computed at
// elaboration time, so this module simply moves wires around and consumes no
// logic resources.

`default_nettype none

module Word_Reverser
#(
    parameter WORD_WIDTH = 0,
    parameter WORD_COUNT = 0,

    // Do not set at instantiation
    parameter TOTAL_WIDTH = WORD_WIDTH * WORD_COUNT
)
(
    input   wire    [TOTAL_WIDTH-1:0]   words_in,
    output  reg     [TOTAL_WIDTH-1:0]   words_out
);

    initial begin
        words_out = {TOTAL_WIDTH{1'b0}};
    end

// For each input word, starting from the right, place it in the output word,
// but starting at the left.

    generate
        genvar i;
        for (i=0; i < WORD_COUNT; i=i+1) begin : per_word
            always @(*) begin
                words_out[WORD_WIDTH*(WORD_COUNT-i-1) +: WORD_WIDTH] = words_in[WORD_WIDTH*i +: WORD_WIDTH];
            end
        end
    endgenerate

endmodule

