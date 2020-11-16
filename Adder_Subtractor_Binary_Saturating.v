
//# Binary Integer Adder/Subtractor, with Saturation

// A signed saturating integer adder/subtractor, with `carry_in`,
// `carry_out`, internal `carries` into each bit.  The operation is selected
// with `add_sub`: setting it to 0 for an add (A+B), and to 1 for a subtract
// (A-B). This assignment conveniently matches the convention of sign bits.

//## Saturation

// If the result of the addition/subtraction falls outside of the inclusive
// minimum or maximum limits, the result is clipped (saturated) to the nearest
// exceeded limit. **The maximum limit must be greater or equal than the
// minimum limit.** If the limits are reversed, such that limit_max
// < limit_min, the result will be meaningless.

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
// adder/subtractors together (there is a subtraction inside the [Arithmetic
// Predicates](./Arithmetic_Predicates_Binary.html) modules), so the total
// carry-chain is twice as long as expected, plus 2 more bits to avoid
// overflow. Most of the time, this will take longer than your clock cycle
// since the carry-chain of arithmetic logic is often a limiting factor in
// timing closure.

`default_nettype none

module Adder_Subtractor_Binary_Saturating
#(
    parameter       WORD_WIDTH          = 0
)
(
    input   wire    [WORD_WIDTH-1:0]    limit_max,
    input   wire    [WORD_WIDTH-1:0]    limit_min,
    input   wire                        add_sub,    // 0/1 -> A+B/A-B
    input   wire                        carry_in,
    input   wire    [WORD_WIDTH-1:0]    A,
    input   wire    [WORD_WIDTH-1:0]    B,
    output  reg     [WORD_WIDTH-1:0]    sum,
    output  reg                         carry_out,
    output  reg     [WORD_WIDTH-1:0]    carries,
    output  wire                        at_limit_max,
    output  wire                        over_limit_max,
    output  wire                        at_limit_min,
    output  wire                        under_limit_min
);

    localparam WORD_ZERO            = {WORD_WIDTH{1'b0}};
    localparam WORD_WIDTH_EXTENDED  = WORD_WIDTH + 1;
    localparam WORD_ZERO_EXTENDED   = {WORD_WIDTH_EXTENDED{1'b0}};

    initial begin
        sum         = WORD_ZERO;
        carry_out   = 1'b0;
        carries     = WORD_ZERO;
    end

// Extend the inputs to prevent overflow over their original range. We extend
// them as signed integers, despite declaring them as unsigned.

    wire [WORD_WIDTH_EXTENDED-1:0] A_extended;

    Width_Adjuster
    #(
        .WORD_WIDTH_IN  (WORD_WIDTH),
        .SIGNED         (1),
        .WORD_WIDTH_OUT (WORD_WIDTH_EXTENDED)
    )
    extend_A
    (
        .original_input     (A),
        .adjusted_output    (A_extended)
    );

    wire [WORD_WIDTH_EXTENDED-1:0] B_extended;

    Width_Adjuster
    #(
        .WORD_WIDTH_IN  (WORD_WIDTH),
        .SIGNED         (1),
        .WORD_WIDTH_OUT (WORD_WIDTH_EXTENDED)
    )
    extend_B
    (
        .original_input     (B),
        .adjusted_output    (B_extended)
    );

// Extend the limits in the same way, as if signed integers. 

    wire [WORD_WIDTH_EXTENDED-1:0] limit_max_extended;

    Width_Adjuster
    #(
        .WORD_WIDTH_IN  (WORD_WIDTH),
        .SIGNED         (1),
        .WORD_WIDTH_OUT (WORD_WIDTH_EXTENDED)
    )
    extend_limit_max
    (
        .original_input     (limit_max),
        .adjusted_output    (limit_max_extended)
    );

    wire [WORD_WIDTH_EXTENDED-1:0] limit_min_extended;

    Width_Adjuster
    #(
        .WORD_WIDTH_IN  (WORD_WIDTH),
        .SIGNED         (1),
        .WORD_WIDTH_OUT (WORD_WIDTH_EXTENDED)
    )
    extend_limit_min
    (
        .original_input     (limit_min),
        .adjusted_output    (limit_min_extended)
    );

// Then select and perform the addition or subtraction in the usual way.
// NOTE: we don't capture the extended `carry_out`, as it will never be set
// properly since the inputs are too small for the `WORD_WIDTH_EXTENDED`. We
// compute the real `carry_out` separately.

    wire [WORD_WIDTH_EXTENDED-1:0] sum_extended;
    wire [WORD_WIDTH_EXTENDED-1:0] carries_extended;

    Adder_Subtractor_Binary
    #(
        .WORD_WIDTH (WORD_WIDTH_EXTENDED)
    )
    extended_add_sub
    (
        .add_sub    (add_sub), // 0/1 -> A+B/A-B
        .carry_in   (carry_in),
        .A          (A_extended),
        .B          (B_extended),
        .sum        (sum_extended),
        // verilator lint_off PINCONNECTEMPTY
        .carry_out  (),
        .carries    (carries_extended),
        .overflow   ()
        // verilator lint_on  PINCONNECTEMPTY
    );

// Since we extended the width by one bit, the original `carry_out` is now the
// carry into that extra bit. Let's also get the original `carries` into each
// bit.

    always @(*) begin
        carry_out = carries_extended [WORD_WIDTH_EXTENDED-1];
        carries   = carries_extended [WORD_WIDTH-1:0];
    end

// Check if `sum_extended` is past the min/max limits.  Using these arithmetic
// predicate modules removes the need to get all the signed declarations
// correct, else we accidentally and silently fall back to unsigned
// comparisons!

    Arithmetic_Predicates_Binary
    #(
        .WORD_WIDTH (WORD_WIDTH_EXTENDED)
    )
    limit_max_check
    (
        .A                  (sum_extended),
        .B                  (limit_max_extended),
        
        // verilator lint_off PINCONNECTEMPTY
        .A_eq_B             (at_limit_max),
        
        .A_lt_B_unsigned    (),
        .A_lte_B_unsigned   (),
        .A_gt_B_unsigned    (),
        .A_gte_B_unsigned   (),
        
        .A_lt_B_signed      (),
        .A_lte_B_signed     (),
        .A_gt_B_signed      (over_limit_max),
        .A_gte_B_signed     ()
        // verilator lint_on  PINCONNECTEMPTY
    );

    Arithmetic_Predicates_Binary
    #(
        .WORD_WIDTH (WORD_WIDTH_EXTENDED)
    )
    limit_min_check
    (
        .A                  (sum_extended),
        .B                  (limit_min_extended),
        
        // verilator lint_off PINCONNECTEMPTY
        .A_eq_B             (at_limit_min),
        
        .A_lt_B_unsigned    (),
        .A_lte_B_unsigned   (),
        .A_gt_B_unsigned    (),
        .A_gte_B_unsigned   (),
        
        .A_lt_B_signed      (under_limit_min),
        .A_lte_B_signed     (),
        .A_gt_B_signed      (),
        .A_gte_B_signed     ()
        // verilator lint_on  PINCONNECTEMPTY
    );

// After, clip the sum to the limits. This must be done as a signed comparison
// so we can place the limits anywhere in the positive or negative integers,
// so long as `limit_max >= limit_min`, as signed integers.  And finally,
// truncate the output back to the input `WORD_WIDTH`.

    reg [WORD_WIDTH_EXTENDED-1:0] sum_extended_clipped = WORD_ZERO_EXTENDED;

    always @(*) begin
        sum_extended_clipped = (over_limit_max  == 1'b1) ? limit_max_extended : sum_extended;
        sum_extended_clipped = (under_limit_min == 1'b1) ? limit_min_extended : sum_extended_clipped;
        sum                  = sum_extended_clipped [WORD_WIDTH-1:0];
    end

endmodule

