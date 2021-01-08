
//# Signed Integer Divider

// Calculates the signed integer `quotient` and `remainder` of the signed
// integer `dividend` and `divisor`. This divider can handle large integers
// (e.g. 128 bits), without impacting clock speed, at the expense of extra
// latency.

//## Example Values

// <pre>
//  22 /   7 =  3 rem  1
// -22 /   7 = -3 rem -1
//  22 /  -7 = -3 rem  1
// -22 /  -7 =  3 rem -1
//   7 /  22 =  0 rem  7
//  -7 / -22 =  0 rem -7
//  -7 /  22 =  0 rem -7
//   7 / -22 =  0 rem  7
//   0 /   0 = -1 rem  0 (raises divide_by_zero)
//  22 /   0 = -1 rem 22 (raises divide_by_zero)
// -22 /   0 =  1 rem 22 (raises divide_by_zero)</pre>

//## Algorithm

// This module implements division as iterated conditional subtraction of
// multiples of the `divisor` from the `dividend`, just as one would do
// manually on paper. The algorithm is described in more detail inside the
// [Remainder](./Remainder_Integer_Signed.html) and
// [Quotient](./Quotient_Integer_Signed.html) modules.

// Iterated subtraction is not the fastest algorithm, but all faster
// algorithms depend on multiplication, which requires a quadratically
// increasing amount of multiplication hardware as the bit width increases.

//## Architecture

// The Remainder and Quotient modules synchronize each division step
// calculation through a [Skid Buffer Pipeline](./Skid_Buffer_Pipeline.html)
// and coordinate the start and end of their calculations with [Pipeline
// Fork](./Pipeline_Fork_Eager.html) and [Pipeline Join](./Pipeline_Join.html)
// modules. Each division step addition/subtraction is done using
// a [Multiprecision
// Adder/Subtractor](./Adder_Subtractor_Binary_Multiprecision.html) to avoid
// excessive area and carry-chain critical paths.  This division of work
// allows buffering control and data as necessary to maintain a high clock
// frequency.

//## Operation

// Start a division by completing the input ready/valid handshake, and read
// out the results by completing the output handshake. Set `WORD_WIDTH` to the
// width of your integers, and `STEP_WORD_WIDTH` to an *equal or smaller
// number*, which will be the width of the internal adder/subtractors.  If the
// area is too large, or the carry-chains form the critical path, decrease
// `STEP_WORD_WIDTH`, which will proportionately decrease the area and the
// carry-chain length, and increase the latency.  If control between Remainder
// and Quotient calculations becomes the critical path, increase
// `PIPELINE_STAGES_SYNC`, which has a negligible impact on area and
// moderately increases latency.

//## Latency

// The latency is *approximately* equal to `WORD_WIDTH / STEP_WORD_WIDTH`
// cycles per bit, plus one cycle per bit for each `PIPELINE_STAGES_SYNC`,
// plus one cycle overall for the input and output handshakes each.

//## Ports and Constants

`default_nettype none

module Divider_Integer_Signed
#(
    parameter WORD_WIDTH            = 0,
    parameter STEP_WORD_WIDTH       = 0,
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

// Buffers the input handshake and replicates it to the Remainder and Quotient
// modules.

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

// At each division step, the Remainder module signals to the Quotient module
// if the current division step is OK (meaning: the current
// addition/subtraction left a valid intermediate remainder), and so that the
// Quotient should be updated. 

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
        .STEP_WORD_WIDTH    (STEP_WORD_WIDTH)
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

// Since the Remainder and Quotient modules can get physically large, we need
// to optionally buffer the control path between them.

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
        .STEP_WORD_WIDTH    (STEP_WORD_WIDTH)
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

//## Output Pipeline Join

// Synchronizes and buffers the output handshakes of the Remainder and
// Quotient modules into the output handshake.

// A `dummy` signal is necessary since we have to use the same data width for
// all handshakes, and the Quotient output is short one bit. The dummy wire,
// and its associated logic, are not connected to any destination and so will
// optimize away. (This may raise a warning in your CAD tools.)

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

