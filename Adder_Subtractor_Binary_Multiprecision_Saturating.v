
//# Multiprecision Binary Integer Adder/Subtractor, with Saturation

// A signed staturating binary integer adder/subtractor, which does arithmetic over
// `WORD_WIDTH` words as a sequence of smaller `STEP_WORD_WIDTH` operations to
// save area and increase operating speed at the price of extra latency.

// The main use of this circuit is to avoid CAD problems which can emerge at
// large integer bit widths (e.g.: 128 bits): the area of added pipeline
// registers would become quite large, and the CAD tools can fail to retime
// them completely into the extra-wide adder logic, thus failing to reach
// a high operating frequency and slowing down the rest of the system.  *There
// are notes in the code which point out the critical paths you can expect to
// see (or not).*

// Also, if we don't need a result every cycle, regular pipelining is
// wasteful: it unnecessarily duplicates the input/output data storage, and
// makes poor use of the adder/subtractor logic (e.g.: the least-significant
// bits are used once, then sit idle for multiple cycles while the higher bits
// are computed).

// Since the result latency depends on the ratio of `WORD_WIDTH` to
// `STEP_WORD_WIDTH` and whether that ratio is a whole integer, the inputs are
// set with a ready/valid handshake, and can be updated after the output
// handshake completes.

// Addition/subtraction is selected with `add_sub`: 0 for an add (`A+B`), and
// 1 for a subtract (`A-B`). This assignment conveniently matches the
// convention of sign bits. *Note that the `overflow` bit is only meaningful
// for signed numbers. For unsigned numbers, use `carry_out` instead.*

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

//## Ports and Constants

`default_nettype none

module Adder_Subtractor_Binary_Multiprecision_Saturating
#(
    parameter       WORD_WIDTH          = 0,
    parameter       STEP_WORD_WIDTH     = 0,
    parameter       EXTRA_PIPE_STAGES   = 0 // Use if predicates are critical path
)
(
    input   wire                        clock,
    input   wire                        clock_enable,
    input   wire                        clear,

    input   wire                        input_valid,
    output  wire                        input_ready,

    input   wire    [WORD_WIDTH-1:0]    limit_max,
    input   wire    [WORD_WIDTH-1:0]    limit_min,
    input   wire                        add_sub,    // 0/1 -> A+B/A-B
    input   wire    [WORD_WIDTH-1:0]    A,
    input   wire    [WORD_WIDTH-1:0]    B,

    output  wire                        output_valid,
    input   wire                        output_ready,

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

    wire [WORD_WIDTH_EXTENDED-1:0]  sum_extended;
    wire [WORD_WIDTH_EXTENDED-1:0]  carries_extended;

    wire                            output_valid_addsub;
    // Correct, but confuses Veril*tor
    // verilator lint_off UNOPTFLAT
    wire                            output_ready_addsub;
    // verilator lint_on  UNOPTFLAT

    Adder_Subtractor_Binary_Multiprecision
    #(
        .WORD_WIDTH         (WORD_WIDTH_EXTENDED),
        .STEP_WORD_WIDTH    (STEP_WORD_WIDTH)
    )
    extended_add_sub
    (
        .clock              (clock),
        .clock_enable       (clock_enable),
        .clear              (clear),

        .input_valid        (input_valid),
        .input_ready        (input_ready),

        .add_sub            (add_sub), // 0/1 -> A+B/A-B
        .A                  (A_extended),
        .B                  (B_extended),

        .output_valid       (output_valid_addsub),
        .output_ready       (output_ready_addsub),

        // verilator lint_off PINCONNECTEMPTY
        .sum                (sum_extended),
        .carry_out          (),
        .carries            (carries_extended),
        .overflow           ()
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

    wire                            input_valid_max;
    wire                            input_ready_max;

    wire                            input_valid_min;
    wire                            input_ready_min;

    wire [WORD_WIDTH_EXTENDED-1:0]  sum_extended_max;
    wire [WORD_WIDTH_EXTENDED-1:0]  sum_extended_min;

// Since we are doing multi-cycle calculations here, we could multiplex one
// predicates module, but that's more stateful and complex. So let's run two
// in parallel, as usual, and the fork/join takes care of all the
// synchronization and data handling.

    localparam LIMIT_CHECK_COUNT = 2;

    Pipeline_Fork_Eager
    #(
        .WORD_WIDTH     (WORD_WIDTH_EXTENDED),
        .OUTPUT_COUNT   (LIMIT_CHECK_COUNT)
    )
    fork_to_limit_checks
    (
        .clock          (clock),
        .clear          (clear),

        .input_valid    (output_valid_addsub),
        .input_ready    (output_ready_addsub),
        .input_data     (sum_extended),

        .output_valid   ({input_valid_max,  input_valid_min}),
        .output_ready   ({input_ready_max,  input_ready_min}),
        .output_data    ({sum_extended_max, sum_extended_min})
    );

    wire    output_valid_max;
    wire    output_ready_max;

    wire    at_limit_max_raw;
    wire    over_limit_max_raw;

    Arithmetic_Predicates_Binary_Multiprecision
    #(
        .WORD_WIDTH         (WORD_WIDTH_EXTENDED),
        .STEP_WORD_WIDTH    (STEP_WORD_WIDTH),
        .PIPELINE_DEPTH     (EXTRA_PIPE_STAGES)
    )
    limit_max_check
    (
        .clock              (clock),
        .clock_enable       (clock_enable),
        .clear              (clear),

        .input_valid        (input_valid_max),
        .input_ready        (input_ready_max),

        .A                  (sum_extended_max),
        .B                  (limit_max_extended),

        .output_valid       (output_valid_max),
        .output_ready       (output_ready_max),

        // verilator lint_off PINCONNECTEMPTY
        .A_eq_B             (at_limit_max_raw),

        .A_lt_B_unsigned    (),
        .A_lte_B_unsigned   (),
        .A_gt_B_unsigned    (),
        .A_gte_B_unsigned   (),

        .A_lt_B_signed      (),
        .A_lte_B_signed     (),
        .A_gt_B_signed      (over_limit_max_raw),
        .A_gte_B_signed     ()
        // verilator lint_on  PINCONNECTEMPTY
    );

    wire    output_valid_min;
    wire    output_ready_min;

    wire    at_limit_min_raw;
    wire    under_limit_min_raw;

    Arithmetic_Predicates_Binary_Multiprecision
    #(
        .WORD_WIDTH         (WORD_WIDTH_EXTENDED),
        .STEP_WORD_WIDTH    (STEP_WORD_WIDTH),
        .PIPELINE_DEPTH     (EXTRA_PIPE_STAGES)
    )
    limit_min_check
    (
        .clock              (clock),
        .clock_enable       (clock_enable),
        .clear              (clear),

        .input_valid        (input_valid_min),
        .input_ready        (input_ready_min),

        .A                  (sum_extended_min),
        .B                  (limit_min_extended),

        .output_valid       (output_valid_min),
        .output_ready       (output_ready_min),

        // verilator lint_off PINCONNECTEMPTY
        .A_eq_B             (at_limit_min_raw),

        .A_lt_B_unsigned    (),
        .A_lte_B_unsigned   (),
        .A_gt_B_unsigned    (),
        .A_gte_B_unsigned   (),

        .A_lt_B_signed      (under_limit_min_raw),
        .A_lte_B_signed     (),
        .A_gt_B_signed      (),
        .A_gte_B_signed     ()
        // verilator lint_on  PINCONNECTEMPTY
    );

    localparam LIMIT_COUNT = 1 + 1;

    Pipeline_Join
    #(
        .WORD_WIDTH     (LIMIT_COUNT),
        .INPUT_COUNT    (LIMIT_CHECK_COUNT)
    )
    join_from_limit_checks
    (
        .clock          (clock),
        .clear          (clear),

        .input_valid    ({output_valid_max, output_valid_min}),
        .input_ready    ({output_ready_max, output_ready_min}),
        .input_data     ({at_limit_max_raw, over_limit_max_raw, at_limit_min_raw, under_limit_min_raw}),

        .output_valid   (output_valid),
        .output_ready   (output_ready),
        .output_data    ({at_limit_max, over_limit_max, at_limit_min, under_limit_min})
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


