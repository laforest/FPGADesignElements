
//# Multiprecision Signed Binary Accumulator, with Saturation

// Adds/subtracts the signed `increment_value` to the signed
// `accumulated_value`, or loads a new `load_value` to replace the
// `accumulated_value`. A concurrent load and increment will first load, then
// increment the loaded value.

// Deasserting `clock_enable` freezes the accumulator: new increments, and
// loads, are ignored, the internal pipeline (if any) holds steady, and all
// outputs remain static.

//## Saturation

// If the increment **or the load** would cause the accumulator to go past the
// signed minimum or maximum limits, the accumulator will saturate at the
// nearest limit value and also raise one or more of the min/max limit signals
// until the next operation. **The maximum limit must be greater or equal than
// the minimum limit.** If the limits are reversed, such that limit_max
// < limit_min, the result will be meaningless.

`default_nettype none

module Accumulator_Binary_Multiprecision_Saturating
#(
    parameter                   WORD_WIDTH          = 0,
    parameter                   STEP_WORD_WIDTH     = 0,
    parameter                   EXTRA_PIPE_STAGES   = -1 // Use for critical paths in Accumulator
)
(
    input   wire                        clock,
    input   wire                        clock_enable,
    input   wire                        clear,

    input   wire                        increment_add_sub,  // 0/1 --> +/-
    input   wire    [WORD_WIDTH-1:0]    increment_value,
    input   wire                        increment_valid,
    output  wire                        increment_ready,

    input   wire    [WORD_WIDTH-1:0]    load_value,
    input   wire                        load_valid,
    output  wire                        load_ready,

    // These are implicitly reloaded by both the load and increment input handshakes.
    input   wire    [WORD_WIDTH-1:0]    limit_max,
    input   wire    [WORD_WIDTH-1:0]    limit_min,

    output  wire                        output_valid,
    input   wire                        output_ready,

    output  wire    [WORD_WIDTH-1:0]    accumulated_value,
    output  wire                        accumulated_value_carry_out,
    output  wire    [WORD_WIDTH-1:0]    accumulated_value_carries,
    output  wire                        accumulated_value_at_limit_max,
    output  wire                        accumulated_value_over_limit_max,
    output  wire                        accumulated_value_at_limit_min,
    output  wire                        accumulated_value_under_limit_min
);

    localparam WORD_ZERO = {WORD_WIDTH{1'b0}};

// If we are *loading* then substitute the `accumulated_value` with zero, and
// the `increment` with the `load_value`.  Converting a load to an addition to
// zero prevents us from loading a value outside the given limits, which could
// really upset things in the enclosing logic, and will set the output status
// bits correctly.

// *`load` takes priority over a concurrent `increment`*, so a load
// concurrent with an increment will result in the accumulator holding
// `load_value + increment_value`.

    wire [WORD_WIDTH-1:0] accumulated_value_selected;
    wire [WORD_WIDTH-1:0] increment_selected;

    Pipeline_Merge_Priority
    #(
        .WORD_WIDTH     (WORD_WIDTH + WORD_WIDTH),
        .INPUT_COUNT    (2),
        .IMPLEMENTATION ("AND")
    )
    load_priority
    (
        .clock          (clock),
        .clear          (clear),

        .input_valid    ({increment_valid,                     load_valid}),
        .input_ready    ({increment_ready,                     load_ready}),
        .input_data     ({increment_value, accumulated_value,  load_value, WORD_ZERO}),

        .output_valid   (add_increment_input_valid),
        .output_ready   (add_increment_input_ready),
        .output_data    ({increment_selected, accumulated_value_selected})
    );

// Apply the increment to the current accumulator value, or the load value to
// an accumulator value of zero, with saturation.

    wire add_increment_input_valid;
    wire add_increment_input_ready;

    Adder_Subtractor_Binary_Multiprecision_Saturating
    #(
        .WORD_WIDTH         (WORD_WIDTH),
        .STEP_WORD_WIDTH    (STEP_WORD_WIDTH),
        .EXTRA_PIPE_STAGES  (EXTRA_PIPE_STAGES)  // Use if predicates are critical path
    )
    add_increment
    (
        .clock              (clock),
        .clock_enable       (clock_enable),
        .clear              (clear),

        .input_valid        (add_increment_input_valid),
        .input_ready        (add_increment_input_ready),

        .limit_max          (limit_max),
        .limit_min          (limit_min),
        .add_sub            (increment_add_sub), // 0/1 -> A+B/A-B
        .A                  (accumulated_value_selected),
        .B                  (increment_selected),

        .output_valid       (output_valid),
        .output_ready       (output_ready),

        .sum                (accumulated_value),
        .carry_out          (accumulated_value_carry_out),
        .carries            (accumulated_value_carries),
        .at_limit_max       (accumulated_value_at_limit_max),
        .over_limit_max     (accumulated_value_over_limit_max),
        .at_limit_min       (accumulated_value_at_limit_min),
        .under_limit_min    (accumulated_value_under_limit_min)
    );

endmodule

