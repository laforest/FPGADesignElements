
//# Triadic Boolean Operator (Dual Output)

// Computes one of the 256 possible three-variable (triadic) Boolean operations,
// selectable at run-time, on the `A`, `B`, and `C` input words, with optional
// dual output.

// We could implement a triadic Boolean operator in hardware the same way as
// we did the [dyadic Boolean operator](./Dyadic_Boolean_Operator.html), but
// with an 8:1 multiplexer instead of a 4:1 multiplexer. However, unlike a 4:1
// mux, an 8:1 mux doesn't fit into a 6-LUT on a modern FPGA, which distances
// our design from the underlying FPGA hardware: we might not be able to
// pipeline it as required for best operating speed, we are more at the mercy
// of the register retiming and logic packing of the CAD tool, and as we'll
// see, we lock ourselves out of a useful break in abstraction which gives
// a triadic operator special uses.

// Instead, we can decompose a triadic Boolean function `f(A,B,C)` into two
// dyadic sub-functions based on the two possible values of `C`: `g(A,B)
// = f(A,B,0)` and `h(A,B) = f(A,B,1)`. We can then reconstruct the original
// triadic function like so: `f(A,B,C) = (g(A,B) & ~C) | (h(A,B) & C)`: the
// value of `C` selects one of the two dyadic Boolean functions of `A` and
// `B`.  Note that `C` selects bit-wise, not word-wise: each bit of `C`
// selects the corresponding bit of `g(A,B)` or `h(A,B)`.  This useful
// mathematical identity is known as "Shannon Decomposition" or "Boole's
// Expansion Theorem".

// We can use a triadic operator to implement very diverse functions:

// * [Majority](./Bit_Voting.html): `AB | AC | BC`, which is used in Triple Modular Redundancy (TMR). 
// * [Minority](./Bit_Voting.html), which tells you if a TMR unit had a corrected error. 
// * Given `A`, `B`, and their sum `A+B`, you can [recover the carries into each bit position](./CarryIn_Binary.html) like so: `A ^ B ^ (A+B)`. This can allow you to find overflows in packed sub-word parallel arithmetic (e.g.: adding two 32-bit words as two vectors of 4 bytes) 
// * Bitfield masking and swapping between `A` and `B`, as selected by the bitmask `C`.

// When used to implement Boolean functions with 4 or more variables
// (tetradic or n-adic), triadic functions approximately halve the number of steps
// required compared to using ordinary dyadic functions. This is likely one
// reason the NVIDIA Maxwell GPUs implemented triadic Boolean functions with
// the `LOP3` instruction, and Intel CPUs with AVX-512 support with the
// `VPTERNLOG` instruction.

// However, if you look at the implementation of `f(A,B,C)` above, we always
// throw away half of the total work done by both dyadic halves `g(A,B)` and
// `h(A,B)`.  Discarded work is a clue that we are missing out on some
// computational capacity or efficiency. So let's provide a way to output that
// discarded work. We can add a second output multiplexer, driven by the same
// functions `g(A,B)` and `h(A,B)`, but controlled by an inverted version of
// `C`, called `D`, which outputs the bits not selected by `C`. And, instead
// of hardcoding `D` as the inverse of `C`, we can control it with a 1-bit
// `dual` signal. If `dual` is not set, then `C` and `D` are the same, and
// both triadic outputs are identical.

// With two outputs, our triadic Boolean operator can now do more. When `dual` is set:

// * We can compute 2 independent [dyadic Boolean functions](./Dyadic_Boolean_Operations.html).
// * We can set `g(A,B)` and `h(A,B)` to always output `A` or `B`, and depending on `C`, send those outputs either straight through or crossed-over. This acts as a Banyan Switch, which is the building block of a lot of switching networks.

// I have not gone through the trouble of defining all 256 triadic Boolean
// operations, but given the [definitions of the 16 possible dyadic Boolean
// operations](./Dyadic_Boolean_Operations.html), you can easily create
// triadic definitions as needed: write out the 8-entry truth table for your
// desired triadic function, split the table into two 4-entry truth tables
// with the most-significant input bit (`C`, as above) always 1 in one table,
// and always 0 in the other, then use those two dyadic definitions as
// functions `g(A,B)` and `h(A,B)` as explained above.

// You can, of course, repeat this process to implement tetradic or n-adic
// functions, but the *size* of the truth tables grows exponentially
// (2<sup>n</sup>), and the *number* of truth tables grows super-exponentially
// (65,536 possible tetradic functions, or 2<sup>2<sup>n</sup></sup> for
// n-adic functions), so there are increasingly fewer functions of general
// interest in that space, with some exceptions such as [bit
// reductions](./Bit_Reducer.html) and [word reductions](./Word_Reducer.html).

`include "Dyadic_Boolean_Operations.vh"

`default_nettype none

module Triadic_Boolean_Operator
#(
    parameter WORD_WIDTH = 0
)
(
    input   wire    [`DYADIC_TRUTH_TABLE_WIDTH-1:0]     dyadic_truth_table_1,
    input   wire    [`DYADIC_TRUTH_TABLE_WIDTH-1:0]     dyadic_truth_table_2,
    input   wire    [WORD_WIDTH-1:0]                    word_A,
    input   wire    [WORD_WIDTH-1:0]                    word_B,
    input   wire    [WORD_WIDTH-1:0]                    word_C,
    input   wire                                        dual,
    output  wire    [WORD_WIDTH-1:0]                    result_1,
    output  wire    [WORD_WIDTH-1:0]                    result_2
    
);

    localparam WORD_ZERO = {WORD_WIDTH{1'b0}};

// First dyadic Boolean operation: `g(A,B)`

    wire [WORD_WIDTH-1:0] g;

    Dyadic_Boolean_Operator
    #(
        .WORD_WIDTH     (WORD_WIDTH)
    )
    first
    (
        .truth_table    (dyadic_truth_table_1),
        .word_A         (word_A),
        .word_B         (word_B),
        .result         (g)
    );

// Second dyadic Boolean operation: `h(A,B)`

    wire [WORD_WIDTH-1:0] h;

    Dyadic_Boolean_Operator
    #(
        .WORD_WIDTH     (WORD_WIDTH)
    )
    second
    (
        .truth_table    (dyadic_truth_table_2),
        .word_A         (word_A),
        .word_B         (word_B),
        .result         (h)
    );

// Now we select each bit from either `g(A,B)` or `h(A,B)`, giving us the
// first result.

    Multiplexer_Bitwise_2to1
    #(
        .WORD_WIDTH (WORD_WIDTH)
    )
    select_1
    (
        .bitmask    (word_C),
        .word_in_0  (g),
        .word_in_1  (h), 
        .word_out   (result_1)
    );

// Then, conditionally invert `word_C` if `dual` is set.

    reg [WORD_WIDTH-1:0] word_D = WORD_ZERO;

    always @(*) begin
        word_D = (dual == 1'b1) ? ~word_C : word_C;
    end

// And select again for the second result, but selected by `word_D`, giving us
// all the bits *not* selected by the previous multiplexer if `dual` is set,
// else the same bits.

    Multiplexer_Bitwise_2to1
    #(
        .WORD_WIDTH (WORD_WIDTH)
    )
    select_2
    (
        .bitmask    (word_D),
        .word_in_0  (g),
        .word_in_1  (h), 
        .word_out   (result_2)
    );

endmodule

