
//# Debouncer (Low Latency)

// A digital debouncer for mechanical inputs (e.g.: mechanical and optical
// switches) which can run on the system clock, introduces only 4 or 5 clock
// cycles of latency, and whose rising and falling debouncing delays can be
// altered dynamically (i.e.: if the clock frequency changes, or the
// mechanical input changes).

//## Background

// * For discussion and some experimental data on switch bounce, see Jack
// Ganssle's ["A Guide to Debouncing, or, How to Debounce a Contact in Two
// Easy Pages"](http://www.ganssle.com/debouncing.htm).

// * Horowitz' and Hill's *"The Art of Electronics"* also has some information
// on signal integrity, measurement, and debouncing scattered throughout.

// * Finally, Dan Gissequist's ["How to eliminate button bounces with digital
// logic"](https://zipcpu.com/blog/2017/08/04/debouncing.html), goes over some
// pitfalls and arrives to a similar design as shown here.

//## A Warning About External Noise

// **This debouncer depends on the assumption that any change on the input is
// caused solely by the connected mechanism.** It will **NOT** reliably filter
// out random spikes and glitches from other sources such as EMI
// (ElectroMagnetic Interference). If a glitch gets captured by the debouncer,
// it will be interpreted as a switch event (rising or falling).

// On the other hand, this debouncer is very tolerant of slow signal edges and
// does not require digital-like quick input transitions. This debouncer only
// requires that the input eventually reaches and stays at a valid high or low
// logic level. Thus, you can liberally use analog filtering at the input if
// your electrical environment is noisy.

//## Theory of Operation

// In the absence of external noise, a switch in a steady opened or closed
// state will provide a steady logic level to the input (high or low,
// depending on the setup). Thus, when we open a closed switch or close an
// open switch, the logic level at the input (high or low) can only change to
// the other level via a positive (low to high) or negative (high to low)
// edge. The switch may then bounce for a while, causing a number of
// alternating edges, but the first edge is always valid.  (The last edge is
// also valid, but we can't know when it will happen, which is another way to
// state the problem.)

// We detect this initial positive or negative edge and use it to immediately
// set the output of the debouncer so it matches the new logic level the
// switch will eventually provide once it settles. This initial edge also
// starts a counter which freezes the internal state of the debouncer
// until the switch has settled. Thus, we can report a switch opening or
// closing after only a few clock cycles, and push the wait time to the
// interval *between* the switch opening and closing, in parallel with
// whatever action the switch starts. 

//## Calibration

// Normally, for normal human-scale operation of a switch, a single
// conservative bounce time estimate suffices to filter out both closing and
// opening switch bounce. However, all switches are different, and may be used
// with a very uneven duty cycle (e.g.: rapid short pulses), so a separate
// wait time for both rising and falling transitions can be set.

// FIXME add notes and discussion on calibration and check of correct
// operation

`default_nettype none

module Debouncer_Low_Latency
#(
    parameter WORD_WIDTH        = 22,    // Wide enough to hold largest delay.
    parameter INITIAL_INPUT     = 1'b0, // 1'b0 or 1'b1. The input rest state.
    parameter EXTRA_CDC_STAGES  = 0     // Must be 0 or greater.
)
(
    input   wire                        clock,
    input   wire                        clear,
    input   wire                        enable,

    input   wire    [WORD_WIDTH-1:0]    delay_cycles_rising,
    input   wire    [WORD_WIDTH-1:0]    delay_cycles_falling,

    input   wire                        input_raw,
    output  reg                         input_falling,
    output  reg                         input_rising,
    output  wire                        input_clean,

    // For calibration and testing only
    output  reg                         diag_captured_input,
    output  reg                         diag_synchronized_input,
    output  reg                         diag_ignoring_input
);

    initial begin
        input_falling           = 1'b0;
        input_rising            = 1'b0;
        diag_captured_input     = INITIAL_INPUT;
        diag_synchronized_input = INITIAL_INPUT;
        diag_ignoring_input     = 1'b0;
    end

// Let's generate counter values of the correct width.

    localparam  COUNTER_ONE   = {{WORD_WIDTH-1{1'b0}},1'b1};
    localparam  COUNTER_ZERO  = {WORD_WIDTH{1'b0}};

// First, capture the input in an I/O register.  We expect the CAD tool to do
// this for us, but let's provide attributes to ask explicitly.  This will
// filter out *some* glitches and marginal input levels too, as well as
// provide a way to enable the input.

    wire captured_input;

    (* IOB = "true" *)  // Vivado
    (* useioff = 1 *)   // Quartus

    Register
    #(
        .WORD_WIDTH     (1),
        .RESET_VALUE    (INITIAL_INPUT)
    )
    input_capture
    (
        .clock          (clock),
        .clock_enable   (enable),
        .clear          (clear),
        .data_in        (input_raw),
        .data_out       (captured_input)
    );

    always @(*) begin
        diag_captured_input = captured_input;
    end

// Then, synchronize the captured input to the clock, noise and all.
// This will filter out marginal inputs causing metastability, and glitches
// will either get dropped, or converted to proper 1-cycle pulses.
// Add stages if necessary (likely if you have *very* slow level transitions).
// From here on, the switch noise is a clean digital signal we can process.

    wire synchronized_input;

    CDC_Synchronizer
    #(
        .EXTRA_DEPTH        (EXTRA_CDC_STAGES)  // Must be 0 or greater
    )
    input_synchronizer
    (
        .receiving_clock    (clock),
        .bit_in             (captured_input),
        .bit_out            (synchronized_input)
    );

    always @(*) begin
        diag_synchronized_input = synchronized_input;
    end

// Separately detect rising and falling edges on the input.  This allows us to
// react immediately when the switch opens or closes.  The premise is that if
// a switch is stable in one state, and no external noise exists, then the
// first observed edge can only signify a change in switch state and we can
// report it immediately.

// The rest of the switching time, with its noise, is not important. We only
// need to wait it out in parallel, by loading the counter with a non-zero
// value at that instant and ignoring the input while the counter counts down
// to zero.

    reg counter_load = 1'b0;
    reg counter_run  = 1'b0;

    always @(*) begin
        input_rising    = (synchronized_input == 1'b1) && (input_clean   == 1'b0) && (counter_run == 1'b0);
        input_falling   = (synchronized_input == 1'b0) && (input_clean   == 1'b1) && (counter_run == 1'b0);
        counter_load    = (input_rising       == 1'b1) || (input_falling == 1'b1);
    end

    always @(*) begin
        diag_ignoring_input = (counter_run == 1'b1);
    end

// Capture the gated edge detection pulses in a latch, where each type of
// pulse sets the latch to mirror the state the switch is entering, based on
// the first detected edge.

    Pulse_Latch
    #(
        .RESET_VALUE    (INITIAL_INPUT)
    )
    input_mirror
    (
        .clock          (clock),
        .clear          (input_falling),
        .pulse_in       (input_rising),
        .level_out      (input_clean)
    );

// Finally, when a rising or falling edge is detected, load (and start) the delay counter,
// which disables edge detection while running down to zero. A different value
// may be loaded for rising and falling edges.

    wire [WORD_WIDTH-1:0] delay_cycles;

    Multiplexer_One_Hot
    #(
        .WORD_WIDTH     (WORD_WIDTH),
        .WORD_COUNT     (2),
        .OPERATION      ("OR"),
        .IMPLEMENTATION ("AND")
    )
    delay_select
    (
        .selectors      ({input_falling,        input_rising}),
        .words_in       ({delay_cycles_falling, delay_cycles_rising}),
        .word_out       (delay_cycles)
    );

    wire [WORD_WIDTH-1:0] count;

    Counter_Binary
    #(
        .WORD_WIDTH     (WORD_WIDTH),
        .INCREMENT      (COUNTER_ONE),
        .INITIAL_COUNT  (COUNTER_ZERO)
    )
    delay_counter
    (
        .clock          (clock),
        .clear          (clear),
        .up_down        (1'b1), // 0/1 --> up/down
        .run            (counter_run),
        .load           (counter_load),
        .load_count     (delay_cycles),
        .carry_in       (1'b0),
        // verilator lint_off PINCONNECTEMPTY
        .carry_out      (),
        // verilator lint_on  PINCONNECTEMPTY
        .count          (count)
    );

    always @(*) begin
        counter_run = (count != COUNTER_ZERO);
    end

endmodule

