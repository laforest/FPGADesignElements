//# Duty Cycle Generator

// Outputs a simple waveform which is high or low for a set number of cycles,
// then takes on the opposite state for a set number of cycles. If not
// immediately re-started, the output remains steady in its last state.

// One-shot by default: Pulse `start` high for one cycle to begin. Then
// `finish` pulses high for one cycle during the last clock cycle of the last
// phase of the `duty_cycle_out` output.  However, `finish` can be looped back
// to `start`, or `start` can be tied high, to generate a continuous waveform
// with a duty cycle and frequency determined by the `high_cycles` and
// `low_cycles` counts. *The cycle count for one phase is loaded during the
// last cycle of the previous phase.*

// Which phase comes first is set by the `first_phase` input. A value of `1`
// means the high phase comes first. Note that `first_phase` is only read at
// `start`.

// Asserting `clear` immediately sets `duty_cycle_out` to `INITIAL_OUTPUT` and
// the `state` to `IDLE`.

// **NOTE**: The limit case of a cycle count of zero is equal to a cycle count of
// one. It takes one cycle to transition from phase to phase, so a zero length
// phase would result in a constant output, and while adding state transitions
// to support that is possible, it's pointless. If you need to stop the
// output, either assert `clear` or stop pulsing `start`.

//## Use cases

// * Feeding a bit stream, synchronized to `start`, to `first_phase` will
// produce a Manchester-encoded version of the bit stream.
// * Altering the `high_cycles` and `low_cycles` values, while keeping their
// sum constant, produces a variable duty cycle signal of constant frequency,
// useful for driving servos, Pulse-Width Modulation, or to filter into a DC
// analog value.
// * Conversely, keeping the `high_cycles` and `low_cycles` ratio constant,
// but scaling their values up and down, preserves the duty cycle but alters
// the frequency of the output.
// * You can generate a framing signal for a bit stream to indicate which
// bits are header or body, based on the `start` of a frame.

`default_nettype none

module Duty_Cycle_Generator
#(
    parameter COUNT_WIDTH       = 0,
    parameter INITIAL_OUTPUT    = 1'b0
)
(
    input   wire                        clock,
    input   wire                        clear,

    input   wire                        start,
    output  reg                         finish,

    input   wire                        first_phase, // 0/1 -> low/high

    input   wire    [COUNT_WIDTH-1:0]   high_cycles,
    input   wire    [COUNT_WIDTH-1:0]   low_cycles,

    output  wire                        duty_cycle_out
);

    localparam COUNT_ZERO = {COUNT_WIDTH{1'b0}};

    initial begin
        finish = 1'b0;
    end

// Define the states. We always output a low and a high phase, starting in
// either order, then we can either immediately start a new sequence (e.g.:
// going from `LOW_SECOND` to `LOW_FIRST`), or wait in `IDLE`. 

    localparam STATE_WIDTH = 3;

    localparam [STATE_WIDTH-1:0] IDLE         = 'd0;
    localparam [STATE_WIDTH-1:0] LOW_FIRST    = 'd1;
    localparam [STATE_WIDTH-1:0] HIGH_SECOND  = 'd2;
    localparam [STATE_WIDTH-1:0] HIGH_FIRST   = 'd3;
    localparam [STATE_WIDTH-1:0] LOW_SECOND   = 'd4;
    // States 5 through 7 are unreachable. Could be checked as an error.

    wire [STATE_WIDTH-1:0] state;
    reg  [STATE_WIDTH-1:0] state_next = IDLE;

// As the state changes, we load the necessary output value, otherwise the
// output remains steady.

    reg load_output_value   = 1'b0;
    reg output_value        = 1'b0;

    Register
    #(
        .WORD_WIDTH     (1),
        .RESET_VALUE    (INITIAL_OUTPUT)
    )
    output_signal
    (
        .clock          (clock),
        .clock_enable   (load_output_value),
        .clear          (clear),
        .data_in        (output_value),
        .data_out       (duty_cycle_out)
    );

// We count the number of clock cycles in each phase, signalling on the last
// cycle of each phase. (We can halt the count by loading a `phase_cycles` of
// zero, which we do in the IDLE state, which raises `div_by_zero`.)

    reg  [COUNT_WIDTH-1:0]  phase_cycles = COUNT_ZERO;
    wire                    end_of_phase;
    wire                    no_phase;
    reg                     phase_done = 1'b0;

    Pulse_Divider
    #(
        .WORD_WIDTH         (COUNT_WIDTH),
        .INITIAL_DIVISOR    (COUNT_ZERO)
    )
    phase_duration
    (
        .clock              (clock),
        .restart            (1'b0),
        .divisor            (phase_cycles),
        .pulses_in          (1'b1),
        .pulse_out          (end_of_phase),
        .div_by_zero        (no_phase)
    );

// We need to signal the end of phase continuously in the `IDLE` state so we
// can load a new cycle count right away when `start` is eventually asserted.
// In effect, it remembers that a phase has ended in the past, while we wait
// for an indeterminate time in `IDLE`. All other phase endings are handled
// immediately.

    always @(*) begin
        phase_done = (end_of_phase == 1'b1) || (no_phase == 1'b1);
    end

// Define the possible actions on the system, independent of state, based on
// internal control signals and inputs. Here, that's the action to take at the
// end of a phase: we either do nothing or start a low or high phase.

    reg start_no_phase   = 1'b0;
    reg start_low_phase  = 1'b0;
    reg start_high_phase = 1'b0;

    always @(*) begin
        start_no_phase   = (phase_done == 1'b1) && (start == 1'b0);
        start_low_phase  = (phase_done == 1'b1) && (start == 1'b1) && (first_phase == 1'b0);
        start_high_phase = (phase_done == 1'b1) && (start == 1'b1) && (first_phase == 1'b1);
    end

// Define the system transformations as a function of state and action.
// These are the edges on the state diagram.

    reg start_low_first         = 1'b0; // Start with the low phase first,
    reg low_done_to_high        = 1'b0; // then move to the high phase second.
    reg high_done               = 1'b0; // When high phase is done and we don't start a new phase
    reg high_done_start_low     = 1'b0; // When high phase is done and we start a low phase
    reg high_done_start_high    = 1'b0; // When high phase is done and we start another high phase

    reg start_high_first        = 1'b0; // Start with the high phase first,
    reg high_done_to_low        = 1'b0; // the move to the low phase second.
    reg low_done                = 1'b0; // When low phase is done and we don't start a new phase
    reg low_done_start_low      = 1'b0; // When low phase is done and we start another low phase
    reg low_done_start_high     = 1'b0; // When low phase is done and we start a high phase

    always @(*) begin
        start_low_first         = (state == IDLE)        && (start_low_phase  == 1'b1);
        low_done_to_high        = (state == LOW_FIRST)   && (phase_done       == 1'b1);
        high_done               = (state == HIGH_SECOND) && (start_no_phase   == 1'b1);
        high_done_start_low     = (state == HIGH_SECOND) && (start_low_phase  == 1'b1);
        high_done_start_high    = (state == HIGH_SECOND) && (start_high_phase == 1'b1);

        start_high_first        = (state == IDLE)        && (start_high_phase == 1'b1);
        high_done_to_low        = (state == HIGH_FIRST)  && (phase_done       == 1'b1);
        low_done                = (state == LOW_SECOND)  && (start_no_phase   == 1'b1);
        low_done_start_low      = (state == LOW_SECOND)  && (start_low_phase  == 1'b1);
        low_done_start_high     = (state == LOW_SECOND)  && (start_high_phase == 1'b1);
    end

// Define the next state function: the state each transformation leads to.

    always @(*) begin
        state_next = (start_low_first       == 1'b1) ? LOW_FIRST    : state;
        state_next = (low_done_to_high      == 1'b1) ? HIGH_SECOND  : state_next;
        state_next = (high_done             == 1'b1) ? IDLE         : state_next;
        state_next = (high_done_start_low   == 1'b1) ? LOW_FIRST    : state_next;
        state_next = (high_done_start_high  == 1'b1) ? HIGH_FIRST   : state_next;

        state_next = (start_high_first      == 1'b1) ? HIGH_FIRST   : state_next;
        state_next = (high_done_to_low      == 1'b1) ? LOW_SECOND   : state_next;
        state_next = (low_done              == 1'b1) ? IDLE         : state_next;
        state_next = (low_done_start_low    == 1'b1) ? LOW_FIRST    : state_next;
        state_next = (low_done_start_high   == 1'b1) ? HIGH_FIRST   : state_next;
    end
    
    Register
    #(
        .WORD_WIDTH     (STATE_WIDTH),
        .RESET_VALUE    (IDLE)
    )
    state_storage
    (
        .clock          (clock),
        .clock_enable   (1'b1),
        .clear          (clear),
        .data_in        (state_next),
        .data_out       (state)
    );

// From the states and transformations, compute the control logic.

    always @(*) begin

        // Signal when we've completed the high/low pair of phases.

        finish = (phase_done == 1'b1) && ((state == LOW_SECOND) || (state == HIGH_SECOND));

        // When the current phase is done, load the next value for the next phase.
        // Checking the `state_next` is an optimization to prevent the
        // `output_signal` register from constantly re-loading while `IDLE`.
        // This isn't necessary, but having useless loads obscures function
        // and may waste power (when more than just a single bit like here).

        load_output_value = (phase_done == 1'b1) && (state_next != IDLE);

        // As we change states, what value should the output change to, or
        // stay steady with the current output (by omitting those transitions
        // here).

        output_value = (start_low_first      == 1'b1) ? 1'b0 : duty_cycle_out;
        output_value = (low_done_to_high     == 1'b1) ? 1'b1 : output_value;
        output_value = (high_done_start_low  == 1'b1) ? 1'b0 : output_value;
        output_value = (start_high_first     == 1'b1) ? 1'b1 : output_value;
        output_value = (high_done_to_low     == 1'b1) ? 1'b0 : output_value;
        output_value = (low_done_start_high  == 1'b1) ? 1'b1 : output_value;

        // As we change states, how long should the next phase last?
        // Otherwise, the phase remains steady by disabling the count with
        // a value of zero.

        phase_cycles = (start_low_first      == 1'b1) ? low_cycles  : COUNT_ZERO;
        phase_cycles = (low_done_to_high     == 1'b1) ? high_cycles : phase_cycles;
        phase_cycles = (high_done_start_low  == 1'b1) ? low_cycles  : phase_cycles;
        phase_cycles = (high_done_start_high == 1'b1) ? high_cycles : phase_cycles;
        phase_cycles = (start_high_first     == 1'b1) ? high_cycles : phase_cycles;
        phase_cycles = (high_done_to_low     == 1'b1) ? low_cycles  : phase_cycles;
        phase_cycles = (low_done_start_low   == 1'b1) ? low_cycles  : phase_cycles;
        phase_cycles = (low_done_start_high  == 1'b1) ? high_cycles : phase_cycles;
    end

endmodule

