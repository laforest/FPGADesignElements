//# Duty Cycle Generator

// Outputs a simple waveform which is high for a set number of cycles, then
// low for a set number of cycles. One-shot by default, but can be looped to
// generate a continuous waveform with a set duty cycle and frequency.

// Pulse start high for one cycle to begin. finish pulses high for one cycle
// during the last clock cycle of the duty_cycle_out output. Loop finish to
// start as necessary.

// Which phase comes first is set by the first_phase input. A 1 means the high
// phase comes first. Note that first_phase is only read after both phases
// have completed.

// Feeding a synchronized serial bit stream to first_phase will produce
// a Manchester encoded version of the bit stream.

`default_nettype none

module Duty_Cycle_Generator
#(
    parameter COUNT_WIDTH = 0
)
(
    input   wire                        clock,
    input   wire                        clear,

    input   wire                        start,
    output  wire                        finish,

    input   wire                        first_phase, // 0/1 -> low/high

    input   wire    [COUNT_WIDTH-1:0]   high_cycles,
    input   wire    [COUNT_WIDTH-1:0]   low_cycles,

    output  wire                        duty_cycle_out
);

    localparam COUNT_ONE  = {{COUNT_WIDTH-1{1'b0}},1'b1};
    localparam COUNT_ZERO = {COUNT_WIDTH{1'b0}};

// The counter loads the value for one phase, then the other, counting from
// the initial cycle count down to 1, where it decides which count to load
// next.

    reg                     run_counter  = 1'b0;
    reg                     load_counter = 1'b0;
    reg  [COUNT_WIDTH-1:0]  phase_cycles = COUNT_ZERO;
    wire [COUNT_WIDTH-1:0]  phase_count;

    Counter_Binary
    #(
        .WORD_WIDTH     (COUNT_WIDTH),
        .INCREMENT      (COUNT_ONE),
        .INITIAL_COUNT  (COUNT_ZERO)
    )
    phase_duration
    (
        .clock          (clock),
        .clear          (clear),
        .up_down        (1'b1), // 0/1 --> up/down
        .run            (run_counter),
        .load           (load_counter),
        .load_count     (phase_cycles),
        .carry_in       (1'b0),
        .carry_out      (),
        .count          (phase_count)
    );

// Define the possible actions on the system, independent of state.

    reg phase_done       = 1'b0;
    reg start_low_phase  = 1'b0;
    reg start_high_phase = 1'b0;

    always @(*) begin
        phase_done       = (phase_count == COUNT_ONE);
        start_no_phase   = (phase_done  == 1'b1) && (start == 1'b0);
        start_low_phase  = (phase_done  == 1'b1) && (start == 1'b1) && (first_phase == 1'b0);
        start_high_phase = (phase_done  == 1'b1) && (start == 1'b1) && (first_phase == 1'b1);
    end

// Define the states. We always output a low and a high phase, starting in
// either order.

    localparam STATE_WIDTH = 3;

    localparam [STATE_WIDTH-1:0] IDLE         = 'd0;
    localparam [STATE_WIDTH-1:0] LOW_FIRST    = 'd1;
    localparam [STATE_WIDTH-1:0] HIGH_SECOND  = 'd2;
    localparam [STATE_WIDTH-1:0] HIGH_FIRST   = 'd3;
    localparam [STATE_WIDTH-1:0] LOW_SECOND   = 'd4;
    // States 5 through 7 are unreachable. Could be checked as an error.

    wire [STATE_WIDTH-1:0] state;
    reg  [STATE_WIDTH-1:0] state_next = IDLE;

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
        high_done               = (state == HIGH_SECOND) && (phase_done       == 1'b1);
        high_done_start_low     = (state == HIGH_SECOND) && (start_low_phase  == 1'b1);
        high_done_start_high    = (state == HIGH_SECOND) && (start_high_phase == 1'b1);

        start_high_first        = (state == IDLE)        && (start_high_phase == 1'b1);
        high_done_to_low        = (state == HIGH_FIRST)  && (phase_done       == 1'b1);
        low_done                = (state == LOW_SECOND)  && (phase_done       == 1'b1);
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



endmodule

