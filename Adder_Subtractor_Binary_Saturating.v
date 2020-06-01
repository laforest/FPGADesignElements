
//# Binary Integer Adder/Subtractor, with Saturation

// This is a basic signed integer adder/subtractor, with carry-in and
// carry-out.  The operation is selected with `add_sub`: setting it to 0 for
// an add (A+B), and to 1 for a subtract (A-B). This assignment matches the
// convention of sign bits, which may end up being convenient.

//## Saturation

// If the result of the addition/subtraction falls outside of the inclusive
// minimum or maximum limits, the result is clipped (saturated) to the nearest
// exceeded limit. **The maximum limit must be greater or equal than the
// minimum limit.** If the limits are reversed, such that max_limit
// < min_limit, the result will be meaningless.

// Internally, we perform the addition/subtraction on WORD_WIDTH + 1 bits.
// Since the limits must be within the range of WORD_WIDTH-wide numbers, there
// can never be an overflow or underflow. Instead, we signal if we have
// reached or would have exceeded the limits at the last incrementation.  The
// saturation logic is a pair of simple signed comparisons in the larger
// range. This is also likely optimal, as the delay from one extra bit of
// carry is less than that of any extra logic to handle overflows.

// Also, we internally perform the addition/subtraction as unsigned so we can
// easily handle the carry_in bit. The signed comparisons are done in
// a separate module which implements signed/unsigned comparisons as raw
// logic, to avoid having to make sure all compared values are declared
// signed, else the comparison silently defaults to unsigned!

//## Maintaining high operating frequency

// You will very likely need to pipeline the *inputs* (for better retiming) of
// this module inside the enclosing module since we are chaining
// adder/subtractors together (there is a subtraction inside the
// Arithmetic_Predicates_Binary modules), so the total carry-chain is twice as
// long as expected, plus 2 more bits to avoid overflow. Most of the time,
// this will take longer than your clock cycle since the carry-chain of
// arithmetic logic is often a limiting factor in timing closure.

`default_nettype none

module Adder_Subtractor_Binary_Saturating
#(
    parameter       WORD_WIDTH          = 0
)
(
    input   wire    [WORD_WIDTH-1:0]    max_limit,
    input   wire    [WORD_WIDTH-1:0]    min_limit,
    input   wire                        add_sub,    // 0/1 -> A+B/A-B
    input   wire                        carry_in,
    input   wire    [WORD_WIDTH-1:0]    A_in,
    input   wire    [WORD_WIDTH-1:0]    B_in,
    output  reg     [WORD_WIDTH-1:0]    sum_out,
    output  wire                        carry_out,
    output  wire                        at_max_limit,
    output  wire                        over_max_limit,
    output  wire                        at_min_limit,
    output  wire                        under_min_limit
);

    localparam WORD_ZERO            = {WORD_WIDTH{1'b0}};
    localparam WORD_WIDTH_EXTENDED  = WORD_WIDTH + 1;
    localparam WORD_ZERO_EXTENDED   = {WORD_WIDTH_EXTENDED{1'b0}};

    initial begin
        sum_out     = WORD_ZERO;
    end

// Extend the inputs to prevent overflow over their original range. We extend
// them as signed integers, despite declaring them as unsigned.

    wire [WORD_WIDTH_EXTENDED-1:0] A_in_extended;

    Width_Adjuster
    #(
        .WORD_WIDTH_IN  (WORD_WIDTH),
        .SIGNED         (1),
        .WORD_WIDTH_OUT (WORD_WIDTH_EXTENDED)  // Must be greater or equal to WORD_WIDTH_IN
    )
    extend_A
    (
        .original_input     (A_in),
        .adjusted_output    (A_in_extended)
    );

    wire [WORD_WIDTH_EXTENDED-1:0] B_in_extended;

    Width_Adjuster
    #(
        .WORD_WIDTH_IN  (WORD_WIDTH),
        .SIGNED         (1),
        .WORD_WIDTH_OUT (WORD_WIDTH_EXTENDED)  // Must be greater or equal to WORD_WIDTH_IN
    )
    extend_B
    (
        .original_input     (B_in),
        .adjusted_output    (B_in_extended)
    );

// Extend the limits in the same way, as if signed integers. 

    wire [WORD_WIDTH_EXTENDED-1:0] max_limit_extended;

    Width_Adjuster
    #(
        .WORD_WIDTH_IN  (WORD_WIDTH),
        .SIGNED         (1),
        .WORD_WIDTH_OUT (WORD_WIDTH_EXTENDED)  // Must be greater or equal to WORD_WIDTH_IN
    )
    extend_max_limit
    (
        .original_input     (max_limit),
        .adjusted_output    (max_limit_extended)
    );

    wire [WORD_WIDTH_EXTENDED-1:0] min_limit_extended;

    Width_Adjuster
    #(
        .WORD_WIDTH_IN  (WORD_WIDTH),
        .SIGNED         (1),
        .WORD_WIDTH_OUT (WORD_WIDTH_EXTENDED)  // Must be greater or equal to WORD_WIDTH_IN
    )
    extend_min_limit
    (
        .original_input     (min_limit),
        .adjusted_output    (min_limit_extended)
    );

// Then select and perform the addition or subtraction in the usual way.
// NOTE: we don't capture the extended carry_out, as it will never be set
// properly since the inputs are too small. We compute the real carry_out
// separately.

    wire [WORD_WIDTH_EXTENDED-1:0] sum_out_extended;

    Adder_Subtractor_Binary
    #(
        .WORD_WIDTH (WORD_WIDTH_EXTENDED)
    )
    extended_add_sub
    (
        .add_sub    (add_sub), // 0/1 -> A+B/A-B
        .carry_in   (carry_in),
        .A_in       (A_in_extended),
        .B_in       (B_in_extended),
        .sum_out    (sum_out_extended),
        // verilator lint_off PINCONNECTEMPTY
        .carry_out  ()
        // verilator lint_on  PINCONNECTEMPTY
    );

// Since we extended the width by one bit, the original carry_out is now the
// carry_in of that extra bit. Let's reconstruct it.

    CarryIn_Binary
    #(
        .WORD_WIDTH (1)
    )
    reconstruct_carry_out
    (
        .A          (A_in_extended      [WORD_WIDTH_EXTENDED-1]),
        .B          (B_in_extended      [WORD_WIDTH_EXTENDED-1]),
        .sum        (sum_out_extended   [WORD_WIDTH_EXTENDED-1]),
        .carryin    (carry_out)
    );

// Check if the sum_out_extended is past the min/max limits.  Using these
// arithmetic predicate modules removes the need to get all the signed
// declarations correct, else we accidentally and silently fall back to
// unsigned comparisons!

    Arithmetic_Predicates_Binary
    #(
        .WORD_WIDTH (WORD_WIDTH_EXTENDED)
    )
    max_limit_check
    (
        .A                  (sum_out_extended),
        .B                  (max_limit_extended),
        
        // verilator lint_off PINCONNECTEMPTY
        .A_eq_B             (at_max_limit),
        
        .A_lt_B_unsigned    (),
        .A_lte_B_unsigned   (),
        .A_gt_B_unsigned    (),
        .A_gte_B_unsigned   (),
        
        .A_lt_B_signed      (),
        .A_lte_B_signed     (),
        .A_gt_B_signed      (over_max_limit),
        .A_gte_B_signed     ()
        // verilator lint_on  PINCONNECTEMPTY
    );

    Arithmetic_Predicates_Binary
    #(
        .WORD_WIDTH (WORD_WIDTH_EXTENDED)
    )
    min_limit_check
    (
        .A                  (sum_out_extended),
        .B                  (min_limit_extended),
        
        // verilator lint_off PINCONNECTEMPTY
        .A_eq_B             (at_min_limit),
        
        .A_lt_B_unsigned    (),
        .A_lte_B_unsigned   (),
        .A_gt_B_unsigned    (),
        .A_gte_B_unsigned   (),
        
        .A_lt_B_signed      (under_min_limit),
        .A_lte_B_signed     (),
        .A_gt_B_signed      (),
        .A_gte_B_signed     ()
        // verilator lint_on  PINCONNECTEMPTY
    );

// After, clip the sum to the limits. This must be done as a signed comparison
// so we can place the limits anywhere in the positive or negative integers,
// so long as max_limit >= min_limit, as signed integers.  And finally,
// truncate the output back to the input WORD_WIDTH.

    reg [WORD_WIDTH_EXTENDED-1:0] sum_out_extended_clipped = WORD_ZERO_EXTENDED;

    always @(*) begin
        sum_out_extended_clipped    = (over_max_limit  == 1'b1) ? max_limit_extended : sum_out_extended;
        sum_out_extended_clipped    = (under_min_limit == 1'b1) ? min_limit_extended : sum_out_extended_clipped;
        sum_out                     = sum_out_extended_clipped [WORD_WIDTH-1:0];
    end

endmodule

