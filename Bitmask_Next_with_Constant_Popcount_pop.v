
//# Bitmask: Next with Constant Popcount (via Population Count)

// Credit: [Hacker's Delight](./reading.html#Warren2013), Section 2-1: Manipulating Rightmost Bits, "A Novel Application"

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
// * y = r | [(1 << (popcount(x^r)-2-2c))-1]

// While this version uses the relatively large [Population
// Count](./Population_Count.html) module instead of the much smaller
// [Logarithm of Powers of Two](./Logarithm_of_Powers_of_Two.html) module, its
// variable bit-shift is only for the fixed input value of 1, which requires
// much less hardware than the full-word shifter found in the [ntz-based
// version](./Bitmask_Next_with_Constant_Popcount_ntz.html). I don't yet know
// whether this is a good tradeoff for speed or area.

`default_nettype none

module Bitmask_Next_with_Constant_Popcount_pop
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

    localparam ZERO = {WORD_WIDTH{1'b0}};
    localparam ONE  = {{WORD_WIDTH-1{1'b0}},1'b1};
    localparam TWO  = {{WORD_WIDTH-2{1'b0}},2'b10};

    initial begin
        word_out = ZERO;
    end

// We find the least-significant bit set in the bitmask.

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

// Then add that smallest bit to the input, causing any run of consecutive
// 1 bits to ripple up into the next 0 bit. (e.g.: 1001100 -> 1010000)

// We also save the carry-out to later deal with the case where the
// consecutive 1 bits were at the left end of the word and rippled into
// the carry out, so we can wraparound back to the right end without
// information loss.

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

// Now we compute the number of bits which changed after the ripple
// addition. Any changed bits are on the right side of the ripple: the
// left side is always unchanged, except at the limit case where the carry
// out is set.

    wire [WORD_WIDTH-1:0] changed_bits;

    Hamming_Distance
    #(
        .WORD_WIDTH     (WORD_WIDTH)
    )
    calc_changed_bits
    (
        .word_A           (word_in),
        .word_B           (ripple),
        .distance         (changed_bits)
    );

// We need some corrections to the Hamming Distance, which are explained
// later. If we have not reached the left end of the word, then we need
// a correction of two, else zero.

    reg [WORD_WIDTH-1:0] distance_adjustment = ZERO;

    always @(*) begin
        distance_adjustment = (ripple_carry_out == 1'b1) ? ZERO : TWO;
    end
    
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

// If we rippled all the way into the carry bit, then the Hamming Distance is
// necessarily equal to the number of set bits in the bitmask, as the carry
// bit is not included in the Hamming Distance calculation. We need that
// number to wraparound and create the first possible bitmask at the right end
// of the word (e.g.: 11100000 -> 00000111), so we subtract zero instead.

    wire [WORD_WIDTH-1:0] adjusted_distance;

    Adder_Subtractor_Binary
    #(
        .WORD_WIDTH (WORD_WIDTH)
    )
    calc_adjusted_distance
    (
        .add_sub    (1'b1), // 0/1 -> A+B/A-B
        .carry_in   (1'b0),
        .A_in       (changed_bits),
        .B_in       (distance_adjustment),
        .sum_out    (adjusted_distance),
        // verilator lint_off PINCONNECTEMPTY
        .carry_out  ()
        // verilator lint_on  PINCONNECTEMPTY
    );

// To rebuild any lost set bits, we left-shift a 1 bit by the corrected
// Hamming Distance....

    wire [WORD_WIDTH-1:0] shifted_one;

    Bit_Shifter
    #(
        .WORD_WIDTH         (WORD_WIDTH)
    )
    calc_shifted_ones
    (
        .word_in_left       (ZERO),
        .word_in            (ONE),
        .word_in_right      (ZERO),

        .shift_amount       (adjusted_distance),
        .shift_direction    (1'b0), // 0/1 -> left/right

        // verilator lint_off PINCONNECTEMPTY
        .word_out_left      (),
        .word_out           (shifted_one),
        .word_out_right     ()
        // verilator lint_on  PINCONNECTEMPTY
    );

// ...and then subtract 1 to "reverse ripple" that bit into all the bits
// to the right, creating the lost run of set bits at the rightmost
// position. If there was only one bit rippled initially, then no set bit
// was lost, the corrected Hamming Distance was zero, the 1 bit is not
// shifted, and gets subtracted to zero, without affecting other bits.

    wire [WORD_WIDTH-1:0] lost_ones;

    Adder_Subtractor_Binary
    #(
        .WORD_WIDTH (WORD_WIDTH)
    )
    calc_lost_ones
    (
        .add_sub    (1'b1), // 0/1 -> A+B/A-B
        .carry_in   (1'b0),
        .A_in       (shifted_one),
        .B_in       (ONE),
        .sum_out    (lost_ones),
        // verilator lint_off PINCONNECTEMPTY
        .carry_out  ()
        // verilator lint_on  PINCONNECTEMPTY
    );

// Finally, we OR the rippled bits (which contains the unchanged left-most
// part, plus the new set ripple bit) with the reconstructed bits lost to
// the initial ripple (if any). We now have the next bitmask with the same
// number of set bits, in strict incrementing order (a.k.a. lexicographic
// order).

    always @(*) begin
        word_out = ripple | lost_ones;
    end

endmodule

