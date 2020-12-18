
//# Signed Integer Divider

`default_nettype none

module Divider_Integer_Signed
#(
    parameter WORD_WIDTH            = 4,
    parameter PIPELINE_STAGES_CALC  = 0,
    parameter PIPELINE_STAGES_SYNC  = 0
)
(
    input  wire                     clock,
    input  wire                     clear,

    input  wire                     input_valid,
    output wire                     input_ready,
    input  wire [WORD_WIDTH-1:0]    dividend,
    input  wire [WORD_WIDTH-1:0]    divisor,

    output wire                     output_valid,
    input  wire                     output_ready,
    output wire [WORD_WIDTH-1:0]    quotient,
    output wire [WORD_WIDTH-1:0]    remainder,
    output wire                     divide_by_zero
);

    localparam UNIT_COUNT         = 2;
    localparam TOTAL_INPUT_WIDTH  = WORD_WIDTH * UNIT_COUNT;
    localparam TOTAL_OUTPUT_WIDTH = WORD_WIDTH + 1;

//## Input Pipeline Fork

    wire input_valid_remainder;
    wire input_ready_remainder;
    wire input_valid_quotient;
    wire input_ready_quotient;

    wire [WORD_WIDTH-1:0] dividend_remainder;
    wire [WORD_WIDTH-1:0] divisor_remainder;
    wire [WORD_WIDTH-1:0] dividend_quotient;
    wire [WORD_WIDTH-1:0] divisor_quotient;

    Pipeline_Fork_Eager
    #(
        .WORD_WIDTH     (TOTAL_INPUT_WIDTH),
        .OUTPUT_COUNT   (UNIT_COUNT)
    )
    write_to_units
    (
        .clock          (clock),
        .clear          (clear),

        .input_valid    (input_valid),
        .input_ready    (input_ready),
        .input_data     ({dividend, divisor}),

        .output_valid   ({input_valid_remainder, input_valid_quotient}),
        .output_ready   ({input_ready_remainder, input_ready_quotient}),
        .output_data    ({dividend_remainder, divisor_remainder, dividend_quotient, divisor_quotient})
    );

//## Remainder Calculation Unit

    wire output_valid_remainder;
    wire output_ready_remainder;
    wire control_valid_remainder;
    wire control_ready_remainder;

    wire [WORD_WIDTH-1:0] remainder_internal;
    wire                  divide_by_zero_internal;
    wire                  step_ok_remainder;

    Remainder_Integer_Signed
    #(
        .WORD_WIDTH         (WORD_WIDTH),
        .PIPELINE_STAGES    (PIPELINE_STAGES_CALC)
    )
    remainder_calc
    (
        .clock          (clock),
        .clear          (clear),

        .input_valid    (input_valid_remainder),
        .input_ready    (input_ready_remainder),
        .dividend       (dividend_remainder),
        .divisor        (divisor_remainder),

        .output_valid   (output_valid_remainder),
        .output_ready   (output_ready_remainder),
        .remainder      (remainder_internal),
        .divide_by_zero (divide_by_zero_internal),

        .control_valid  (control_valid_remainder),
        .control_ready  (control_ready_remainder),
        .step_ok        (step_ok_remainder)
    );

//## Calculation Synchronization Buffer

    wire control_valid_quotient;
    wire control_ready_quotient;
    wire step_ok_quotient;

    Skid_Buffer_Pipeline
    #(
        .WORD_WIDTH     (1),
        .PIPE_DEPTH     (PIPELINE_STAGES_SYNC)
    )
    buffer_sync
    (
        .clock          (clock),
        .clear          (clear),
        .input_valid    (control_valid_remainder),
        .input_ready    (control_ready_remainder),
        .input_data     (step_ok_remainder),

        .output_valid   (control_valid_quotient),
        .output_ready   (control_ready_quotient),
        .output_data    (step_ok_quotient)
    );

//## Quotient Calculation Unit

    wire output_valid_quotient;
    wire output_ready_quotient;

    wire [WORD_WIDTH-1:0] quotient_internal;

    Quotient_Integer_Signed
    #(
        .WORD_WIDTH         (WORD_WIDTH),
        .PIPELINE_STAGES    (PIPELINE_STAGES_CALC)
    )
    quotient_calc
    (
        .clock          (clock),
        .clear          (clear),

        .input_valid    (input_valid_quotient),
        .input_ready    (input_ready_quotient),
        .dividend_sign  (dividend_quotient [WORD_WIDTH-1]),
        .divisor_sign   (divisor_quotient  [WORD_WIDTH-1]),

        .output_valid   (output_valid_quotient),
        .output_ready   (output_ready_quotient),
        .quotient       (quotient_internal),

        .control_valid  (control_valid_quotient),
        .control_ready  (control_ready_quotient),
        .step_ok        (step_ok_quotient)
    );

//# Output Pipeline Join

    // verilator lint_off UNUSED
    wire dummy;
    // verilator lint_on  UNUSED

    Pipeline_Join
    #(
        .WORD_WIDTH     (TOTAL_OUTPUT_WIDTH),
        .INPUT_COUNT    (UNIT_COUNT)
    )
    read_from_units
    (
        .clock          (clock),
        .clear          (clear),

        .input_valid    ({output_valid_remainder, output_valid_quotient}),
        .input_ready    ({output_ready_remainder, output_ready_quotient}),
        .input_data     ({remainder_internal, divide_by_zero_internal, quotient_internal, 1'b0}),

        .output_valid   (output_valid),
        .output_ready   (output_ready),
        .output_data    ({remainder, divide_by_zero, quotient, dummy})
    );

endmodule

