//# Averager, over Powers of Two Accumulations

// Accumulates a power-of-two number of signed integer samples, then divides
// the total by the same power-of-two, giving us an average without needing
// a full divider.

// Accepts 2<sup>POWER_OF_TWO_EXPONENT</sup> input samples, then makes the
// average available until it is read out. The output is buffered, so a new
// average may be started before the previous average is read out. A stall
// will happen if two averages are pending read-out. A positive edge on
// `restart_average` discards the current input and accumulation, and starts
// a new average.  Adjust `EXTRA_PIPE_STAGES` to maintain clock speed if the
// Accumulator adder becomes the critical path.

//## Overflow

// The width of the Accumulator is internally adjusted so it can never
// overflow, regardless of the input sample sequence. However, should an
// overflow somehow happen, the `input_overflow` signal will hold high until
// either the average is read out or restarted.

// *With apologies to Ned Washington regarding the module instance names...*

//### Ports and Parameters

`default_nettype none

module Averager_Powers_of_Two
#(
    parameter WORD_WIDTH                = 0,
    parameter POWER_OF_TWO_EXPONENT     = 0,
    parameter EXTRA_PIPE_STAGES         = 0
)
(
    input   wire                        clock,
    input   wire                        clear,

    input   wire                        restart_average,

    input   wire                        input_valid,
    output  wire                        input_ready,
    input   wire    [WORD_WIDTH-1:0]    input_sample,
    output  wire                        input_overflow,

    output  wire                        output_valid,
    input   wire                        output_ready,
    output  wire    [WORD_WIDTH-1:0]    output_average
);

//### Constants

// We rarely need this value explicitly, so update it here if your system
// use a different width for Verilog integers.

    localparam VERILOG_INT_WIDTH  = 32;

// The accumulator needs to be wide enough to hold, in the extreme, the sum of
// 2**POWER_OF_TWO_EXPONENT samples, all of maximum magnitude.

    localparam WORD_ZERO            = {WORD_WIDTH{1'b0}};
    localparam ACCUMULATOR_WIDTH    = WORD_WIDTH + POWER_OF_TWO_EXPONENT; 
    localparam ACCUMULATOR_ZERO     = {ACCUMULATOR_WIDTH{1'b0}};

// The counter counts samples from (2^POWER_OF_TWO_EXPONENT)-1 down to 0.

    `include "clog2_function.vh"

    localparam SAMPLE_COUNT         = (2**POWER_OF_TWO_EXPONENT) - 1;
    localparam COUNTER_WIDTH        = clog2(SAMPLE_COUNT);
    localparam COUNTER_ONE          = {{COUNTER_WIDTH-1{1'b0}}, 1'b1};
    localparam COUNTER_ZERO         = {COUNTER_WIDTH{1'b0}};

//### Datapath

// First, convert the input handshake into a pulse interface to the
// Accumulator_Binary.

    wire [WORD_WIDTH-1:0]   input_sample_passed;
    wire                    sample_valid;
    reg                     input_sample_next = 1'b0;

    Pipeline_to_Pulse
    #(
        .WORD_WIDTH             (WORD_WIDTH)
    )
    bring_em_in
    (
        .clock                  (clock),
        .clear                  (clear),

        // Pipeline input
        .valid_in               (input_valid),
        .ready_in               (input_ready),
        .data_in                (input_sample),

        // Pulse interface to connected module input
        .module_data_in         (input_sample_passed),
        .module_data_in_valid   (sample_valid),

        // Signal that the module can accept the next input
        .module_ready           (input_sample_next)
    );

// Then, widen the signed sample to the accumulator width.

    wire [ACCUMULATOR_WIDTH-1:0] sample;

    Width_Adjuster
    #(
        .WORD_WIDTH_IN  (WORD_WIDTH),
        .SIGNED         (1),
        .WORD_WIDTH_OUT (ACCUMULATOR_WIDTH)
    )
    widen_em
    (
        .original_input     (input_sample_passed),
        .adjusted_output    (sample)
    );

// Then, accumulate the samples together, taking any pipelining latency into
// account.  We let the Accumulator_Binary set the pace with its `done`
// signals.  Although the accumulator is wide enough to never overflow, let's
// provide that signal just in case.

    reg                             clear_accumulator   = 1'b0;
    wire                            clear_done;
    wire                            sample_done;
    wire [ACCUMULATOR_WIDTH-1:0]    sample_sum;
    wire                            sample_overflow;

    Accumulator_Binary
    #(
        .EXTRA_PIPE_STAGES  (EXTRA_PIPE_STAGES),
        .WORD_WIDTH         (ACCUMULATOR_WIDTH),
        .INITIAL_VALUE      (ACCUMULATOR_ZERO)
    )
    add_em_up
    (
        .clock                              (clock),
        .clock_enable                       (1'b1),

        .clear                              (clear_accumulator),
        .clear_done                         (clear_done),

        .increment_carry_in                 (1'b0),
        .increment_add_sub                  (1'b0), // 0/1 --> +/-
        .increment_value                    (sample),
        .increment_valid                    (sample_valid),
        .increment_done                     (sample_done),

        .load_value                         (ACCUMULATOR_ZERO),
        .load_valid                         (1'b0),
        // verilator lint_off PINCONNECTEMPTY
        .load_done                          (),
        // verilator lint_on  PINCONNECTEMPTY

        .accumulated_value                  (sample_sum),
        // verilator lint_off PINCONNECTEMPTY
        .accumulated_value_carry_out        (),
        .accumulated_value_carries          (),
        // verilator lint_on  PINCONNECTEMPTY
        .accumulated_value_signed_overflow  (sample_overflow)
    );

// Each time we accumulate a sample, decrement the counter one step.
// When the counter reaches zero after a sample is accumulated, we are done.

    reg                         reset_counter   = 1'b0;
    wire [COUNTER_WIDTH-1:0]    samples_remaining;

    Counter_Binary
    #(
        .WORD_WIDTH     (COUNTER_WIDTH),
        .INCREMENT      (COUNTER_ONE),
        .INITIAL_COUNT  (SAMPLE_COUNT [COUNTER_WIDTH-1:0])
    )
    count_em_down
    (
        .clock          (clock),
        .clear          (reset_counter),

        .up_down        (1'b1), // 0/1 --> up/down
        .run            (sample_valid),

        .load           (1'b0),
        .load_count     (COUNTER_ZERO),

        .carry_in       (1'b0),
        // verilator lint_off PINCONNECTEMPTY
        .carry_out      (),
        .carries        (),
        .overflow       (),
        // verilator lint_on  PINCONNECTEMPTY

        .count          (samples_remaining)
    );

// Since we allow signed samples, division by a power of two is only *mostly*
// a right-shift. There's a little correction required, done here in the
// Divider_Integer_Signed_by_Powers_of_Two module.  Since the exponent is
// a constant power-of-two here, the divider should reduce to a bit of adder
// logic, even though we have to extend the exponent to match the accumulator
// width.

    wire [ACCUMULATOR_WIDTH-1:0] EXPONENT_EXTENDED;

    Width_Adjuster
    #(
        .WORD_WIDTH_IN  (VERILOG_INT_WIDTH),
        .SIGNED         (0),
        .WORD_WIDTH_OUT (ACCUMULATOR_WIDTH)
    )
    make_it_wide
    (
        .original_input     (POWER_OF_TWO_EXPONENT),
        .adjusted_output    (EXPONENT_EXTENDED)
    );

    wire [ACCUMULATOR_WIDTH-1:0] raw_average;

    Divider_Integer_Signed_by_Powers_of_Two
    #(
        .WORD_WIDTH (ACCUMULATOR_WIDTH)
    )
    split_em_up
    (
        .numerator          (sample_sum),
        .exponent_of_two    (EXPONENT_EXTENDED),

        .quotient           (raw_average),
        // verilator lint_off PINCONNECTEMPTY
        .remainder          ()
        // verilator lint_on  PINCONNECTEMPTY
    );

// Then, truncate the result back down to WORD_WIDTH. Because we made sure
// the accumulator should never overflow, and because we work with
// power-of-two number of samples, truncation should never lose information.

    wire [WORD_WIDTH-1:0] truncated_average;

    Width_Adjuster
    #(
        .WORD_WIDTH_IN  (ACCUMULATOR_WIDTH),
        .SIGNED         (1),
        .WORD_WIDTH_OUT (WORD_WIDTH)
    )
    cut_em_down
    (
        .original_input     (raw_average),
        .adjusted_output    (truncated_average)
    );

// Finally, convert the pulse-controlled output to the output pipeline
// handshake interface.

    reg  truncated_average_valid = 1'b0;
    wire average_read_out;

    Pulse_to_Pipeline
    #(
        .WORD_WIDTH             (WORD_WIDTH),
        .OUTPUT_BUFFER_TYPE     ("SKID"),   // "HALF", "SKID", "FIFO"
        .FIFO_BUFFER_DEPTH      (),         // Only for "FIFO"
        .FIFO_BUFFER_RAMSTYLE   ()          // Only for "FIFO"
    )
    bring_em_out
    (
        .clock                  (clock),
        .clear                  (clear),

        // Pipeline output
        .valid_out              (output_valid),
        .ready_out              (output_ready),
        .data_out               (output_average),

        // Pulse interface from connected module
        .module_data_out        (truncated_average),
        .module_data_out_valid  (truncated_average_valid),

        // Signal that the module can accept the next input
        .module_ready           (average_read_out)
    );

//### Control Logic

// Firstly, since `sample_overflow` is reset by consecutive accumulations,
// let's hold it until we start a new average, either by clearing, restarting,
// or reading out the current average once ready. 

    reg clear_overflow = 1'b0;

    Pulse_Latch
    #(
        .RESET_VALUE    (1'b0)
    )
    hold_em_high
    (
        .clock          (clock),
        .clear          (clear_overflow),
        .pulse_in       (sample_overflow),
        .level_out      (input_overflow)
    );

// Then, catch any interruption of the averaging process by a positive edge on
// `restart_average`, cleaning it up to a single cycle pulse.

    wire restart;

    Pulse_Generator
    turn_em_round
    (
        .clock              (clock),
        .level_in           (restart_average),
        .pulse_posedge_out  (restart),
        // verilator lint_off PINCONNECTEMPTY
        .pulse_negedge_out  (),
        .pulse_anyedge_out  ()
        // verilator lint_on  PINCONNECTEMPTY
    );

// At reset, when reading out an average, or when restarting, clear the
// accumulator, any status signals, and the counter.

    always @(*) begin
        clear_accumulator   = (clear == 1'b1) || (average_read_out == 1'b1) || (restart == 1'b1);
        clear_overflow      = (clear_accumulator == 1'b1); 
        reset_counter       = (clear_accumulator == 1'b1);
    end

// Finally, accept a new sample once either the current sample has been
// accumulated, or we are done clearing the accumulator. Provide a new average
// once all samples have been accumulated.

    always @(*) begin
        input_sample_next       = ((sample_done == 1'b1) && (samples_remaining != COUNTER_ZERO)) || (clear_done == 1'b1);
        truncated_average_valid =  (sample_done == 1'b1) && (samples_remaining == COUNTER_ZERO);
    end

endmodule

