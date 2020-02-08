
//# Logarithm of Powers of Two

// Translates a power-of-2 binary value (a one-hot bitmask) into its integer
// base-2 logarithm. For example:

// * log<sub>2</sub>(0001) -> log<sub>2</sub>(2<sup>0</sup>) -> log<sub>2</sub>(1) -> 0
// * log<sub>2</sub>(0010) -> log<sub>2</sub>(2<sup>1</sup>) -> log<sub>2</sub>(2) -> 1
// * log<sub>2</sub>(0100) -> log<sub>2</sub>(2<sup>2</sup>) -> log<sub>2</sub>(4) -> 2
// * log<sub>2</sub>(1000) -> log<sub>2</sub>(2<sup>3</sup>) -> log<sub>2</sub>(8) -> 3

// We can see the logarithm of a power-of-2 is simply the index of the single
// set bit: log<sub>2</sub>(2<sup>set_bit_index</sup>) = set_bit_index.

// If the input is not a power-of-2 (more than one set bit), then this
// implementation will output the bitwise-OR of the logarithm of each set bit
// treated as a power-of-2, which I'm not sure has any use or meaning. To save
// hardware (we'd need a [Population Count](./Population_Count.html) or a pair
// of [Priority Arbiters](./Priority_Arbiter.html)), we don't signal these
// cases.
// Also, this calculation fails if no bits are set, since log<sub>2</sub>(0)
// is undefined, and we cannot output zero as that's a valid logarithm. To
// represent the undefined case, we will set an extra bit to declare the output
// undefined, via a simple NOR-reduction of the input.

// We can't implement using a translation table, as with the
// [Static Address Translator](./Address_Translator_Static.html), since we
// would have to create a table capable of holding all 2<sup>WORD_WIDTH</sup>
// possible values, and that would take a *long* time to synthesize and optimize,
// as well as require a lot of system memory.
// Instead, we precalculate each possible logarithm (one per input bit) and
// gate its value based on whether the corresponding input bit is set. We then
// OR-reduce all these possible logarithms into the final answer. We can use
// this implementation method since the amount of logic scales linearly with
// WORD_WIDTH.

// You can use this module to implement unsigned division by powers-of-2 by
// shifting right by the logarithm value. However, *signed* division by
// powers-of-2 has a complication. See [Hacker's
// Delight](./books.html#Warren2013), Section 10-1, "Signed Division by
// a Known Power of 2". 

// When combined with [Bitmask: Isolate Rightmost
// 1 Bit](./Bitmask_Isolate_Rightmost_1_Bit.html), this module forms the basis
// for the very useful Number of Trailing Zeros (ntz) function. Add a [Word
// Reverser](./Word_Reverser.html) and you can compute Number of Leading Zeros
// (nlz).

`default_nettype none

module Logarithm_of_Powers_of_Two
#(
    parameter WORD_WIDTH = 0
)
(
    input   wire    [WORD_WIDTH-1:0]    one_hot_in,
    output  wire    [WORD_WIDTH-1:0]    logarithm_out,
    output  reg                         logarithm_undefined
);

    localparam WORD_ZERO = {WORD_WIDTH{1'b0}};

    initial begin
        logarithm_undefined = 1'b0;
    end

// To keep the interface clean, logarithm_out has the same WORD_WIDTH as
// one_hot_in. To calculate each possbile logarithm in parallel, we need an
// array of one output word per input bit. But we must use a flat vector here
// instead of an array since we will be passing this vector of words to
// a Word_Reducer module, and we can't pass multidimensional arrays through
// module ports in Verilog-2001. This means you will hit the Verilog vector
// width limit of about a million when WORD_WIDTH reaches about 1024, though
// simulation and synthesis will have become impractically slow long before
// then.

    localparam TOTAL_WIDTH  = WORD_WIDTH * WORD_WIDTH;
    localparam TOTAL_ZERO   = {TOTAL_WIDTH{1'b0}};

    reg [TOTAL_WIDTH-1:0] all_logarithms = TOTAL_ZERO;

// Most of those logarithm output bits remain a constant zero (and so require
// no logic) since representing the value of a binary number up to
// 2<sup>N</sup>-1 require at most log<sub>2</sub>(N) bits. Therefore,
// representing log<sub>2</sub>(2<sup>N</sup>-1) in binary only needs
// log<sub>2</sub>(log<sub>2</sub>(N)) bits, which is a value that grows
// __very__ slowly. Having output bits stuck at zero will raise CAD tool
// warnings, but that's a lot less error-prone than having the enclosing logic
// calculate the required output logarithm bit width.

// This implementation would ultimately fail if the computed logarithm needs
// more bits than a 32-bit Verilog integer. However, as explained above, that
// would require an input value exceeding 2<sup>2<sup>32</sup></sup>-1, which
// is 2<sup>32</sup> bits long. You are not likely to reach this limit.

// So we pre-compute how many bits we will need to represent the logarithm,
// and also create some zero-padding to expand the logarithm back to
// WORD_WIDTH.

    `include "clog2_function.vh"
    localparam LOGARITHM_WIDTH = clog2(WORD_WIDTH);
    localparam PAD_WIDTH = WORD_WIDTH - LOGARITHM_WIDTH;
    localparam PAD = {PAD_WIDTH{1'b0}};

// Then, for each set input bit, put its logarithm (the bit index) into the
// corresponding array word, else put zero. Note how we slice the integer
// logarithm down to the necessary bits and then pad those back up to the
// array word width.

    generate
        genvar i;
        for(i = 0; i < WORD_WIDTH; i = i + 1) begin : per_input_bit
            always @(*) begin
                all_logarithms[WORD_WIDTH*i +: WORD_WIDTH] = (one_hot_in[i] == 1'b1) ? {PAD, i[LOGARITHM_WIDTH-1:0]} : WORD_ZERO;
            end
        end
    endgenerate

// Then, we OR-reduce the array of possible logarithms down to one.

    Word_Reducer
    #(
        .OPERATION  ("OR"),
        .WORD_WIDTH (WORD_WIDTH),
        .WORD_COUNT (WORD_WIDTH)
    )
    combine_logarithms
    (
        .words_in   (all_logarithms),
        .word_out   (logarithm_out)
    );

// Finally, we detect the case where all input bits are zero and the logarithm
// is undefined.

    always @(*) begin
        logarithm_undefined = (one_hot_in == WORD_ZERO);
    end

endmodule

