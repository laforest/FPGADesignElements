
//# A Reliable and Generic Binary Multiplexer

// But first, some background on the problems with multiplexers...

//## Simulation and Synthesis Mismatch

// A pitfall in the Verilog language is the treatment of unknown X values in
// `if` statements, and it can cause a mismatch between the simulated and the
// synthesized behaviours. I have observed this exact mismatch in the field.
// This problem carries over into the design of multiplexers in general.
// Here's a contrived example, where we select one of two possibilities:

//     reg                         selector;
//     reg     [WORD_WIDTH-1:0]    option_A;
//     reg     [WORD_WIDTH-1:0]    option_B;
//     reg     [WORD_WIDTH-1:0]    result;
//     
//     always @(*) begin
//         if (selector == 1'b0) begin
//             result = option_A;
//         end
//         else begin
//             result = option_B;
//         end
//     end

// The problem here happens if `selector` is X or Z-valued. In real hardware,
// we would expect an X or Z `selector` to cause `result` to obtain an
// X value, *but the `if` statement treats X as false, and so falls through to
// the `else` case*. The simulation returns `option_B` while the synthesis
// returns `X`. This difference can also confuse verification efforts, because
// it can show a failure in simulation where there isn't one.

// Instead of `if` statements, we can use the ternary `?:` operator, which
// behaves as expected. Except in cases where both `option_A/option_B`
// evaluate to 1 or 0, an X or Z-valued `selector` will return an X value:

//     always @(*) begin
//         result = (selector == 1'b0) ? option_A : option_B;
//     end

//## Inflexible Implementation

// However, [the ternary operator gets impractical for more that two
// options](./verilog.html#ternary), and the `case` statement gets tedious and
// error-prone as the number of cases increases. And both are too rigid,
// requiring changes to the multiplexer implementation should the number of
// inputs change.

//## A Generic Solution

// Instead of implementing multiple multiplexers of specific sizes, we can
// replace them all with a single multiplexer module, implemented using
// a vector part select, which simulates and synthesizes correctly, and
// accepts a parameterized number of inputs.  In the following code, we can
// think of `selector` as "addressing" one of the `words_in` options.

// Rather than change the number of input ports at each design change, pass
// a concatenation of words to `words_in` with the zeroth element on the
// right. The `selector` then selects one of the input words. If the
// `selector` value is greater than the number of input words, the output is
// unknown (depends on synthesized logic). If the `selector` is X or Z, the
// output is X or Z.

// This multiplexer can also cleanly express little bits of arbitrary logic:
// set the inputs to the possible output values (constant or otherwise) of
// your function, and let the `selector` input get decoded to one of those
// values.

`default_nettype none

module Multiplexer
#(
    parameter       WORD_WIDTH          = 0,
    parameter       ADDR_WIDTH          = 0,
    parameter       INPUT_COUNT         = 0,

    // Do not set at instantiation
    parameter   TOTAL_WIDTH = WORD_WIDTH * INPUT_COUNT
)
(
    input   wire    [ADDR_WIDTH-1:0]    selector,
    input   wire    [TOTAL_WIDTH-1:0]   words_in,
    output  reg     [WORD_WIDTH-1:0]    word_out
);

    initial begin
        word_out = {WORD_WIDTH{1'b0}};
    end

    always @(*) begin
        word_out = words_in[(selector * WORD_WIDTH) +: WORD_WIDTH];
    end

endmodule

//## Portability
//
//There's one problem here: if your HDL of choice does not have an analog of
//Verilog's vector part select, this design can't be translated. Thus, there
//must be another, more structural implementation, which can be ported to
//other HDLs. (*to be continued...*)

