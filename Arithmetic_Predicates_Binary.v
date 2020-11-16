
//# Arithmetic Predicates (Binary)

// Given two integers, `A` and `B`, derives all the possible arithmetic
// predictates (equal, greater-than, less-than-equal, etc...) as both signed
// and unsigned comparisons.

// This code implements "*How the Computer Sets the Comparison Predicates*" in
// Section 2-12 of Henry S. Warren, Jr.'s [Hacker's
// Delight](./reading.html#Warren2013), which describes how to compute all the
// integer comparisons, based on the condition flags generated after
// a (2's-complement) subtraction `A-B`.

`default_nettype none

module Arithmetic_Predicates_Binary
#(
    parameter WORD_WIDTH = 0
)
(
    input   wire    [WORD_WIDTH-1:0]    A,
    input   wire    [WORD_WIDTH-1:0]    B,

    output  reg                         A_eq_B,

    output  reg                         A_lt_B_unsigned,
    output  reg                         A_lte_B_unsigned,
    output  reg                         A_gt_B_unsigned,
    output  reg                         A_gte_B_unsigned,

    output  reg                         A_lt_B_signed,
    output  reg                         A_lte_B_signed,
    output  reg                         A_gt_B_signed,
    output  reg                         A_gte_B_signed
);

    localparam ZERO = {WORD_WIDTH{1'b0}};

    initial begin
        A_eq_B              = 1'b0;
        A_lt_B_unsigned     = 1'b0;
        A_lte_B_unsigned    = 1'b0;
        A_gt_B_unsigned     = 1'b0;
        A_gte_B_unsigned    = 1'b0;
        A_lt_B_signed       = 1'b0;
        A_lte_B_signed      = 1'b0;
        A_gt_B_signed       = 1'b0;
        A_gte_B_signed      = 1'b0;
    end

// First, let's subtract B from A, and get the the carry-out and overflow bits.

    wire [WORD_WIDTH-1:0]   difference;
    wire                    carry_out;
    wire                    overflow_signed;

    Adder_Subtractor_Binary
    #(
        .WORD_WIDTH (WORD_WIDTH)
    )
    subtraction
    (
        .add_sub    (1'b1),    // 0/1 -> A+B/A-B
        .carry_in   (1'b0),
        .A          (A),
        .B          (B),
        .sum        (difference),
        .carry_out  (carry_out),
        // verilator lint_off PINCONNECTEMPTY
        .carries    (),
        // verilator lint_on  PINCONNECTEMPTY
        .overflow   (overflow_signed)
    );

// We now have enough information to compute all the arithmetic predicates.
// Note that in 2's-complement subtraction, the meaning of the carry-out bit
// is reversed, and that special care must be taken for signed comparisons to
// distinguish the carry-out from an overflow.  This code takes advantage of
// the sequential evaluation of blocking assignments in a Verilog procedural
// block to re-use and optimize the logic expressions.

    reg negative = 1'b0;

    always @(*) begin
        negative            = (difference[WORD_WIDTH-1] == 1'b1);
        A_eq_B              = (difference == ZERO);

        A_lt_B_unsigned     = (carry_out == 1'b0);
        A_lte_B_unsigned    = (A_lt_B_unsigned == 1'b1) || (A_eq_B == 1'b1);
        A_gte_B_unsigned    = (carry_out == 1'b1);
        A_gt_B_unsigned     = (A_gte_B_unsigned == 1'b1) && (A_eq_B == 1'b0);

        A_lt_B_signed       = (negative != overflow_signed);
        A_lte_B_signed      = (A_lt_B_signed == 1'b1) || (A_eq_B == 1'b1);
        A_gte_B_signed      = (negative == overflow_signed);
        A_gt_B_signed       = (A_gte_B_signed == 1'b1) && (A_eq_B == 1'b0);
    end

endmodule

