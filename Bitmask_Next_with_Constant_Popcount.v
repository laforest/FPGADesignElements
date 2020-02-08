
//# Bitmask: Next with Constant Popcount

// Credit: [Hacker's Delight](./books.html#Warren2013), Section 2-1: Manipulating Rightmost Bits, "A Novel Application"

// Given a bitmask, gives the next bitmask, in lexicographic order (a.k.a.
// strictly incrementing order), with the same number of bits set (a.k.a. same
// population count). For example: 00100011 -> 00100101.

// Modified here to wraparound correctly at the end of the word, which allows
// you to start with any given bitmask, then know you have tried all possible
// cases when the next bitmask is identical to the starting bitmask.  This
// property avoids having to calculate n-choose-k (for a k-bit bitmask in an
// n-bit word) as a count.

// Implementation, for x -> y:

// * s = x & -x
// * r = s + x
// * c = carry(s + x)
// * y = r | (((x^r) >> (2-2c)) / s)

// While this version requires a division (unlike the popcount-based version),
// the divisor (s) is always a power-of-two ([Bitmask: Isolate Rightmost
// 1 Bit](./Bitmask_Isolate_Rightmost_1_Bit.v)), so the (unsigned) division
// simplifies to a logical shift right by log<sub>2</sub>(s). The two
// consecutive logical shift right can now be combined or commuted:

// * y = r | (((x^r) >> (2-2c)) >> log<sub>2</sub>(s))
// * y = r | (x^r) >> [(2-2c) + log<sub>2</sub>(s)]

// We will use the first form since it doesn't require another adder and the
// first shift is predictable: either by 2 or zero, so we can provide both,
// select one, and feed it to the second, data-dependent shift.

`default_nettype none

module Bitmask_Next_with_Constant_Popcount
#(
    parameter WORD_WIDTH = 32
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

// Compute `c`: also save the carry-out to later deal with the case where the
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
// zero. The extra shift by two is to discard the bit at the position of the
// least-significant set bit (s) which is always zero-ed out by the addition,
// and the next bit (why?)

    wire [WORD_WIDTH-1:0] changed_bits_corrected;
    
    Multiplexer_Binary_Behavioural
    #(
        .WORD_WIDTH     (WORD_WIDTH),
        .ADDR_WIDTH     (1),
        .INPUT_COUNT    (2)
    )
    correction_select
    (
        .selector       (ripple_carry_out),    
        .words_in       ({changed_bits, changed_bits >> 2}),
        .word_out       (changed_bits_corrected)
    );

// If only one bit was rippled leftwards, then the Hamming Distance is
// necessarily two (e.g.: 010010 ripples to 010100, which changes two
// bits). So we subtract two from the Hamming Distance to bring it to zero
// and call that the normal case, as no set bits were lost.  (Remember: we
// want to find the next bitmask with the same number of set bits.)

// If there was a run of 1 bits, these would all have rippled leftwards
// into another bit. The Hamming Distance would therefore be the number of
// 1 bits in that run, plus the changed bit at the left (e.g.: 00111000 ->
// 01000000, for a Hamming Distance of 4). We also subtract two from this
// Hamming Distance. We have to rebuild the lost set bits at the far right
// end of the word, and the corrected Hamming Distance will allow us to do
// that later.

// If we rippled all the way into the carry bit, then the Hamming Distance
// is necessarily equal to the number of bits in the bitmask, as the carry
// bit is not included in the Hamming Distance calculation. We need that
// number to wraparound and create the first possible bitmask at the right
// end of the word (e.g.: 11100000 -> 00000111), so we subtract zero
// instead.

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

// Now we shift the rippled bits back to the right end of the word, giving us
// the next sequence of changed bits with the same number of bits set that is
// also necessarily the smallest possible such...

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
// part, plus the new set ripple bit) with the reconstructed bits lost to
// the initial ripple (if any). We now have the next bitmask with the same
// number of set bits, in strict incrementing order (a.k.a. lexicographic
// order).

    always @(*) begin
        word_out = ripple | changed_bits_shifted;
    end

endmodule

