
//# Signed Binary Accumulator

// Adds/subtracts the signed `increment_value` to the signed
// `accumulated_value` when `increment_valid` is pulsed high *for one cycle*.
// A new increment may be added when `increment_done` pulses high, in the same
// cycle if necessary. 

// Pulsing `load_valid` high for one cycle replaces the `accumulated_value`
// with the `load_value`. A new load can be done when `load_done` pulses high,
// in the same cycle if necessary.

// Pulsing `clear` high for one cycle puts the accumulator back at
// `INITIAL_VALUE`. The accumulator can be cleared again once `clear_done`
// pulses high, in the same cycle if necessary.

// Deasserting `clock_enable` freezes the accumulator: new increments, loads,
// and clears are ignored, the internal pipeline (if any) holds steady, and
// all outputs remain static.

// When chaining accumulators, which may happen if you are incrementing in
// unusual bases where each digit has its own accumulator, AND the
// `accumulated_value_carry_out` of the previous accumulator with the signal
// fed to the `increment_valid` input of the next accumulator. The
// `increment_carry_in` is kept for generality.

//## Overflow

// If the accmulator increments past the max or min signed integer value it
// can hold, the accumulator will roll-over and set the
// `accumulated_value_signed_overflow` bit.  The overflow bit is cleared at
// the next non-overflowing increment, or if the accumulator is cleared or
// loaded.

//## Pipelining and Concurrency

// This module is pipelined to meet timing if necessary. We can't retime this
// pipeline from outside since there is a loop, so we pipeline inside the loop
// here, and let that retime across the
// [Adder_Subtractor_Binary](./Adder_Subtractor_Binary.html) logic.  The price
// to pay is a latency of EXTRA_PIPE_STAGES+1 cycles between an increment,
// load, or clear, and the corresponding "done" signal.  This latency is why
// the input pulses must be asserted *for only one cycle* when
// `EXTRA_PIPE_STAGES` is greater than zero, then wait until the command has
// completed before pulsing again, else any latter increments or loads will
// override the previous ones (since the accumulated_value will have not yet
// updated).

`default_nettype none

module Accumulator_Binary
#(
    parameter                   EXTRA_PIPE_STAGES   = -1,
    parameter                   WORD_WIDTH          =  0,
    parameter [WORD_WIDTH-1:0]  INITIAL_VALUE       =  0
)
(
    input   wire                        clock,
    input   wire                        clock_enable,

    input   wire                        clear,
    output  wire                        clear_done,

    input   wire                        increment_carry_in,
    input   wire                        increment_add_sub,  // 0/1 --> +/-
    input   wire    [WORD_WIDTH-1:0]    increment_value,
    input   wire                        increment_valid,
    output  wire                        increment_done,

    input   wire    [WORD_WIDTH-1:0]    load_value,
    input   wire                        load_valid,
    output  wire                        load_done,

    output  wire    [WORD_WIDTH-1:0]    accumulated_value,
    output  wire                        accumulated_value_carry_out,
    output  wire    [WORD_WIDTH-1:0]    accumulated_value_carries,
    output  wire                        accumulated_value_signed_overflow
);

    localparam WORD_ZERO = {WORD_WIDTH{1'b0}};

// Here, we pipeline the inputs so that all signals further down are in sync,
// and to place the register pipeline inside the loop formed by the
// Adder_Subtractor_Binary and the output register, so we can have forward
// retiming move it into the Adder_Subtractor_Binary logic.  (Backwards
// retiming is more difficult, and not supported by Vivado post-synth
// optimizations)

    wire                    clear_pipelined;

    wire                    increment_carry_in_pipelined;
    wire                    increment_add_sub_pipelined;
    wire [WORD_WIDTH-1:0]   increment_value_pipelined;
    wire                    increment_valid_pipelined;

    wire [WORD_WIDTH-1:0]   load_value_pipelined;
    wire                    load_valid_pipelined;

    wire [WORD_WIDTH-1:0]   accumulated_value_pipelined;

    generate
        if (EXTRA_PIPE_STAGES == 0) begin: no_pipe
            assign clear_pipelined              = clear;
            assign increment_carry_in_pipelined = increment_carry_in;
            assign increment_add_sub_pipelined  = increment_add_sub;
            assign increment_value_pipelined    = increment_value;
            assign increment_valid_pipelined    = increment_valid;
            assign load_value_pipelined         = load_value;
            assign load_valid_pipelined         = load_valid;
            assign accumulated_value_pipelined  = accumulated_value;
        end
        else if (EXTRA_PIPE_STAGES > 0) begin: extra_pipe

            localparam PIPELINE_WIDTH       = (WORD_WIDTH * 3) + 5;
            localparam PIPELINE_WORD_ZERO   = {PIPELINE_WIDTH{1'b0}};
            localparam PIPELINE_ZERO        = {EXTRA_PIPE_STAGES{PIPELINE_WORD_ZERO}};

            Register_Pipeline
            #(
                .WORD_WIDTH     (PIPELINE_WIDTH),
                .PIPE_DEPTH     (EXTRA_PIPE_STAGES),
                // concatenation of each stage initial/reset value
                .RESET_VALUES   (PIPELINE_ZERO)
            )
            accumulator_pipeline
            (
                .clock          (clock),
                .clock_enable   (clock_enable),
                .clear          (1'b0),
                .parallel_load  (1'b0),
                .parallel_in    (PIPELINE_ZERO),
                // verilator lint_off PINCONNECTEMPTY
                .parallel_out   (),
                // verilator lint_on  PINCONNECTEMPTY
                .pipe_in        ({increment_add_sub,           increment_carry_in,           increment_valid,           increment_value,           load_valid,           load_value,           accumulated_value,           clear}),
                .pipe_out       ({increment_add_sub_pipelined, increment_carry_in_pipelined, increment_valid_pipelined, increment_value_pipelined, load_valid_pipelined, load_value_pipelined, accumulated_value_pipelined, clear_pipelined})
            );
        end
    endgenerate

// 
// **After this point, only use the pipelined inputs.**
//

// If we are loading, then substitute the `accumulated_value` with zero, and
// the `increment_value` with the `load_value`. 
// If we are clearing, then substitute the `accumulated_value` with zero, and
// the `increment_value` with the `INITIAL_VALUE`. 
// Converting a load or clear to an addition to zero will set the `carry_out`
// and `signed_overflow` bits correctly.

    reg gate_accumulated_value = 1'b0;

    always @(*) begin
        gate_accumulated_value = (load_valid_pipelined == 1'b1) || (clear_pipelined == 1'b1);
    end

    wire [WORD_WIDTH-1:0] accumulated_value_gated;

    Annuller
    #(
        .WORD_WIDTH     (WORD_WIDTH),
        .IMPLEMENTATION ("AND")
    )
    gate_accumulated
    (
        .annul          (gate_accumulated_value == 1'b1),
        .data_in        (accumulated_value_pipelined),
        .data_out       (accumulated_value_gated)
    );

    reg [WORD_WIDTH-1:0] increment_selected = WORD_ZERO;

    always @(*) begin
        increment_selected = (load_valid_pipelined == 1'b1) ? load_value_pipelined : increment_value_pipelined;
        increment_selected = (clear_pipelined      == 1'b1) ? INITIAL_VALUE        : increment_selected;
    end


// Apply the increment to the current accumulator value, or the load value to
// an accumulator value of zero, or the initial value to an accumulator value
// of zero.

    wire [WORD_WIDTH-1:0]   incremented_value_internal;
    wire                    accumulated_value_carry_out_internal;
    wire [WORD_WIDTH-1:0]   accumulated_value_carries_internal;
    wire                    accumulated_value_signed_overflow_internal;


    Adder_Subtractor_Binary
    #(
        .WORD_WIDTH (WORD_WIDTH)
    )
    add_increment
    (
        .add_sub    (increment_add_sub_pipelined),  // 0/1 -> A+B/A-B
        .carry_in   (increment_carry_in_pipelined),
        .A          (accumulated_value_gated),
        .B          (increment_selected),
        .sum        (incremented_value_internal),
        .carry_out  (accumulated_value_carry_out_internal),
        .carries    (accumulated_value_carries_internal),
        .overflow   (accumulated_value_signed_overflow_internal )
    );

// Then, update the accumulator register and other outputs sychronized to
// it. Update the registers if load or increment or the clear pulse is valid. 

    reg enable_output = 1'b0;

    always @(*) begin
        enable_output  = (increment_valid_pipelined == 1'b1) || (load_valid_pipelined == 1'b1) || (clear_pipelined == 1'b1);
        enable_output  = (enable_output             == 1'b1) && (clock_enable         == 1'b1);
    end

    Register
    #(
        .WORD_WIDTH     (WORD_WIDTH),
        .RESET_VALUE    (INITIAL_VALUE)
    )
    accumulator
    (
        .clock          (clock),
        .clock_enable   (enable_output),
        .clear          (1'b0),
        .data_in        (incremented_value_internal),
        .data_out       (accumulated_value)
    );

    Register
    #(
        .WORD_WIDTH     (1),
        .RESET_VALUE    (1'b0)
    )
    overflow
    (
        .clock          (clock),
        .clock_enable   (enable_output),
        .clear          (1'b0),
        .data_in        (accumulated_value_signed_overflow_internal),
        .data_out       (accumulated_value_signed_overflow)
    );

    Register
    #(
        .WORD_WIDTH     (1),
        .RESET_VALUE    (1'b0)
    )
    carry
    (
        .clock          (clock),
        .clock_enable   (enable_output),
        .clear          (1'b0),
        .data_in        (accumulated_value_carry_out_internal),
        .data_out       (accumulated_value_carry_out)
    );

    Register
    #(
        .WORD_WIDTH     (WORD_WIDTH),
        .RESET_VALUE    (WORD_ZERO)
    )
    carries
    (
        .clock          (clock),
        .clock_enable   (enable_output),
        .clear          (1'b0),
        .data_in        (accumulated_value_carries_internal),
        .data_out       (accumulated_value_carries)
    );

// Finally, output the "done" signals, which are the pipelined command pulses
// plus one register delay to synchronize them to the updated
// `accumulated_value` and related data.

    Register
    #(
        .WORD_WIDTH     (1),
        .RESET_VALUE    (1'b0)
    )
    for_clear
    (
        .clock          (clock),
        .clock_enable   (clock_enable),
        .clear          (1'b0),
        .data_in        (clear_pipelined),
        .data_out       (clear_done)
    );

    Register
    #(
        .WORD_WIDTH     (1),
        .RESET_VALUE    (1'b0)
    )
    for_increment
    (
        .clock          (clock),
        .clock_enable   (clock_enable),
        .clear          (1'b0),
        .data_in        (increment_valid_pipelined),
        .data_out       (increment_done)
    );

    Register
    #(
        .WORD_WIDTH     (1),
        .RESET_VALUE    (1'b0)
    )
    for_load
    (
        .clock          (clock),
        .clock_enable   (clock_enable),
        .clear          (1'b0),
        .data_in        (load_valid_pipelined),
        .data_out       (load_done)
    );

endmodule

