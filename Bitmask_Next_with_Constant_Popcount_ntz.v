
//# Bitmask: Next with Constant Popcount (via Number of Trailing Zeros)

// Credit: [Hacker's Delight](./books.html#Warren2013), Section 2-1: Manipulating Rightmost Bits, "A Novel Application"

// Given a bitmask, gives the next bitmask, in lexicographic order (a.k.a.
// strictly incrementing order), with the same number of bits set (a.k.a. same
// population count). For example: 00100011 -> 00100101.

// Modified here to wraparound correctly at the end of the word, which allows
// you to start with any given bitmask, then know you have tried all possible
// cases when the next bitmask is identical to the starting bitmask.  This
// property avoids having to calculate n-choose-k (for a k-bit bitmask in an
// n-bit word) as a count, or have to detect and handle the highest-valued
// bitmask (i.e.: 11100000) as a special case.

// Implementation, for x -> y:

// * s = x & -x
// * r = s + x
// * c = carry(s + x)
// * y = r | [((x^r) >> (2-2c)) / s]

// While this version requires a division (unlike the [popcount-based
// version](./Bitmask_Next_with_Constant_Popcount_pop.html)), the divisor (s)
// is always a power-of-two ([Bitmask: Isolate Rightmost
// 1 Bit](./Bitmask_Isolate_Rightmost_1_Bit.v)), so the (unsigned) division
// simplifies to a logical shift right by log<sub>2</sub>(s). The two
// consecutive logical shift right can now be combined or commuted, and
// ultimately reduce to a shift by the number of trailing zeros (ntz), with a
// correction of 2 or 0:

// * y = r | [((x^r) >> (2-2c)) >> log<sub>2</sub>(s)]
// * y = r | (x^r) >> [(2-2c) + log<sub>2</sub>(s)]
// * y = r | (x^r) >> [(2-2c) + ntz(x)]

// We will use the first above form since it doesn't require another adder of
// yet another bit width (log<sub>2</sub>(WORD_WIDTH)) which complicates
// writing clean Verilog, and the correction shift is predictable: either by
// 2 or zero, so we can provide both, select one, and feed it to the second,
// data-dependent shift.

// While this version replaces the relatively large [Population
// Count](./Population_Count.html) module with the much smaller [Logarithm of
// Powers of Two](./Logarithm_of_Powers_of_Two.html) module, it does require
// a full-word variable bit-shift, which costs more. I don't yet know whether
// this is a good tradeoff for speed or area.

`default_nettype none

module Bitmask_Next_with_Constant_Popcount_ntz
#(
    parameter WORD_WIDTH = 0
)
(
    input   wire    [WORD_WIDTH-1:0]    word_in,
    output  reg     [WORD_WIDTH-1:0]    word_out
);

// First, let's define some constants used throughout. Rather than expect
// the simulator/synthesizer to get the Verilog spec right and extend
// integers correctly, we defensively specify the entire word.

    localparam WORD_ZERO = {WORD_WIDTH{1'b0}};

    initial begin
        word_out = WORD_ZERO;
    end

// Compute `s`: the least-significant bit set in the bitmask.

    wire [WORD_WIDTH-1:0] smallest;

    Bitmask_Isolate_Rightmost_1_Bit
    #(
        .WORD_WIDTH (WORD_WIDTH)
    )
    find_smallest
    (
        .word_in    (word_in),
        .word_out   (smallest)
    );

// Compute `r`: add that least-significant bit to the input, causing any run
// of consecutive 1 bits at the right to ripple up into the next 0 bit. (e.g.:
// 1001100 -> 1010000)

// Compute `c`: save the carry-out to later deal with the case where the
// consecutive 1 bits were at the left end of the word and rippled up into the
// carry out. In this case, we want to remove a correction to the shift amount
// described later.

    wire [WORD_WIDTH-1:0]   ripple;
    wire                    ripple_carry_out;

    Adder_Subtractor_Binary
    #(
        .WORD_WIDTH (WORD_WIDTH)
    )
    calc_ripple
    (
        .add_sub    (1'b0), // 0/1 -> A+B/A-B
        .carry_in   (1'b0),
        .A_in       (word_in),
        .B_in       (smallest),
        .sum_out    (ripple),
        .carry_out  (ripple_carry_out)
    );

// Compute `x^r`: find the bits which changed after the ripple
// addition. Any changed bits are on the right side of the ripple: the left
// side is always unchanged, except at the limit case where the carry out is
// set.

    reg [WORD_WIDTH-1:0] changed_bits = WORD_ZERO;

    always @(*) begin
        changed_bits = word_in ^ ripple;
    end

// We need a correction to the upcoming right shift: If we have not reached
// the left end of the word, then we need an extra right shift of two, else of
// zero.  Normally, after the ripple, we shift right once to discard the
// now-cleared least-significant set bit, and once more to bring the new
// least-significant set bit into the position of that original
// least-significant set bit. If we rippled right up into the carry bit, then
// no new least-significant set bit is created, so we don't have anything to
// discard and so we don't shift left here.

    reg [WORD_WIDTH-1:0] changed_bits_corrected = WORD_ZERO;

    always @(*) begin
        changed_bits_corrected = (ripple_carry_out == 1'b1) ? changed_bits : changed_bits >> 2;
    end

// Later, we will need to re-align our changed bits back to the right (plus
// any correction), so let's find out the index of the original
// least-significant set bit.

    wire [WORD_WIDTH-1:0] final_shift_amount;

    Logarithm_of_Powers_of_Two
    #(
        .WORD_WIDTH             (WORD_WIDTH)
    )
    calc_final_shift_amount
    (
        .one_hot_in             (smallest),
        .logarithm_out          (final_shift_amount),
        // verilator lint_off PINCONNECTEMPTY
        .logarithm_undefined    ()
        // verilator lint_on  PINCONNECTEMPTY
    );

// Now we shift the post-ripple changed bits (x^r) back to the right end of
// the word (plus correction), giving us the next sequence of changed bits
// with the same number of bits set.

    wire [WORD_WIDTH-1:0] changed_bits_shifted; 

    Bit_Shifter
    #(
        .WORD_WIDTH         (WORD_WIDTH)
    )
    move_changed_bits
    (
        .word_in_left       (WORD_ZERO),
        .word_in            (changed_bits_corrected),
        .word_in_right      (WORD_ZERO),

        .shift_amount       (final_shift_amount),
        .shift_direction    (1'b1), // 0/1 -> left/right

        // verilator lint_off PINCONNECTEMPTY
        .word_out_left      (),
        .word_out           (changed_bits_shifted),
        .word_out_right     ()
        // verilator lint_on  PINCONNECTEMPTY
    );

// Finally, we OR the rippled bits (which contains the unchanged left-most
// part, plus the newly set/cleared ripple bits) with the changed bits lost to
// the initial ripple (if any). We now have the next bitmask with the same
// number of set bits, in strict incrementing order (a.k.a. lexicographic
// order).

    always @(*) begin
        word_out = ripple | changed_bits_shifted;
    end

endmodule

