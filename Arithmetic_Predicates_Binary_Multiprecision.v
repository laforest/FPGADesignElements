
//# Arithmetic Predicates (Binary), using Multiprecision Arithmetic

// Given two integers, `A` and `B`, derives all the possible arithmetic
// predictates (equal, greater-than, less-than-equal, etc...) as both signed
// and unsigned comparisons. Uses multiprecision arithmetic to allow handling
// very wide integers.

// This code implements "*How the Computer Sets the Comparison Predicates*" in
// Section 2-12 of Henry S. Warren, Jr.'s [Hacker's
// Delight](./reading.html#Warren2013), which describes how to compute all the
// integer comparisons, based on the condition flags generated after
// a (2's-complement) subtraction `A-B`.

//## Multiprecision Implementation

// This version uses a [Multiprecision Binary
// Adder/Subtractor](./Adder_Subtractor_Binary_Multiprecision.html) to
// calculate predicates on very wide integers without reducing operating speed
// or greatly increasing area, at the price of a few cycles of latency per
// result (roughly `ceil(WORD_WIDTH / STEP_WORD_WIDTH`) cycles). If you need
// results every cycle, use a conventional [Arithmetic
// Predicates](./Arithmetic_Predicates_Binary.html) and
// [pipeline](./Register_Pipeline_Simple.html) the inputs.

`default_nettype none

module Arithmetic_Predicates_Binary_Multiprecision
#(
    parameter WORD_WIDTH        = 0,
    parameter STEP_WORD_WIDTH   = 0,
    parameter PIPELINE_DEPTH    = -1
)
(
    input   wire                        clock,
    input   wire                        clock_enable,
    input   wire                        clear,

    input   wire                        input_valid,
    output  wire                        input_ready,

    input   wire    [WORD_WIDTH-1:0]    A,
    input   wire    [WORD_WIDTH-1:0]    B,

    output  wire                        output_valid,
    input   wire                        output_ready,

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

// First, let's subtract B from A, and get the the carry-out and overflow
// bits.

// NOTE: we cannot pipeline here, as there is a loop inside the
// Adder_Subtractor_Binary_Multiprecision. We pipeline the raw results later
// below.

    wire [WORD_WIDTH-1:0]   difference_raw;
    wire                    carry_out_raw;
    wire                    overflow_signed_raw;

    wire                    output_valid_raw;
    wire                    output_ready_raw;

    Adder_Subtractor_Binary_Multiprecision
    #(
        .WORD_WIDTH         (WORD_WIDTH),
        .STEP_WORD_WIDTH    (STEP_WORD_WIDTH)
    )
    subtraction
    (
        .clock          (clock),
        .clock_enable   (clock_enable),
        .clear          (clear),

        .input_valid    (input_valid),
        .input_ready    (input_ready),

        .add_sub        (1'b1), // 0/1 -> A+B/A-B
        .A              (A),
        .B              (B),

        .output_valid   (output_valid_raw),
        .output_ready   (output_ready_raw),

        .sum            (difference_raw),
        .carry_out      (carry_out_raw),
        // verilator lint_off PINCONNECTEMPTY
        .carries        (),
        // verilator lint_on  PINCONNECTEMPTY
        .overflow       (overflow_signed_raw)
    );

// Since this module is intended to handle very wide integers, let's add
// optional pipelining here to both retime into the final predicate
// calculation logic, and to allow flexible placement of logic.

    wire [WORD_WIDTH-1:0]   difference;
    wire                    carry_out;
    wire                    overflow_signed;

    localparam PIPELINE_WIDTH = WORD_WIDTH + 1 + 1;

    Skid_Buffer_Pipeline
    #(
        .WORD_WIDTH (PIPELINE_WIDTH),
        .PIPE_DEPTH (PIPELINE_DEPTH)
    )
    subtraction_results
    (
        // If PIPE_DEPTH is zero, these are unused
        // verilator lint_off UNUSED
        .clock          (clock),
        .clear          (clear),
        // verilator lint_on  UNUSED
        .input_valid    (output_valid_raw),
        .input_ready    (output_ready_raw),
        .input_data     ({difference_raw, carry_out_raw, overflow_signed_raw}),

        .output_valid   (output_valid),
        .output_ready   (output_ready),
        .output_data    ({difference,     carry_out,     overflow_signed})
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

