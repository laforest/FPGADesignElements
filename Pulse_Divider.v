
//# Pulse Divider

// Outputs a single-cycle high pulse when `divisor` input pulses have been
// received, thus dividing their number. For example, if `divisor` is 3,
// then:

// * 9 input pulses will produce 3 output pulses
// * 5 input pulses will produce 1 output pulse
// * 7 input pulses will produce 2 output pulses

// Pulses do not have to be distinct: holding the input high for the expected
// number of clock cycles will have the same effect as the same number of
// separate, spaced pulses.

// The `divisor` is reloaded automatically after each output pulse. Any
// changes to the divisor before then do not affect the current pulse
// division. However, asserting `restart` for one cycle will force the
// `divisor` to reload and the pulse division to restart. Holding restart
// `high` will halt the pulse divider. A `restart` pulse is not required after
// startup (there is built-in initialization logic): you can send pulses in
// right away.

//## Uses

// * Signal when a number of events have happened.
// * Generate a periodic enable pulse derived from your main clock. (tie
// `pulses_in` to 1)
// * Perform integer division: the number of output pulses after your input
// pulses are done is the quotient, the number of input pulses you have to then
// provide to get one more output pulse is the remainder if less than
// `divisor`, else it's zero (i.e.: it's the remainder modulo `divisor`).

`default_nettype none

module Pulse_Divider
#(
    parameter                   WORD_WIDTH      = 16,
    parameter [WORD_WIDTH-1:0]  INITIAL_DIVISOR = 3
)
(
    input  wire                     clock,
    input  wire                     restart,
    input  wire [WORD_WIDTH-1:0]    divisor,
    input  wire                     pulses_in,
    output reg                      pulse_out
);

    initial begin
        pulse_out = 1'b0;
    end

    localparam WORD_ZERO = {WORD_WIDTH{1'b0}};
    localparam WORD_ONE  = {{WORD_WIDTH-1{1'b0}}, 1'b1};

// The core of the pulse divider is a simple down counter: we count from
// `divisor` down to zero, signal an output pulse, and reload the counter with
// `divisor`. You can think of the counter value as "input pulses remaining
// before an output pulse". So a loaded `divisor` of 3 would accept 3 input
// pulses to count "2, 1, 0", at which point `pulse_out` goes high, the
// counter sets-up to reload the `divisor`, and everything returns to start
// conditions at the next clock edge.

// However, there are two corner cases: the initial start-up, and
// when an input pulse is received during reload. These cases are dealt with
// further down.

    reg                     run         = 1'b0;
    reg                     load        = 1'b0;
    reg  [WORD_WIDTH-1:0]   load_count  = WORD_ZERO;
    wire [WORD_WIDTH-1:0]   count;

    Counter_Binary
    #(
        .WORD_WIDTH     (WORD_WIDTH),
        .INCREMENT      (WORD_ONE),
        .INITIAL_COUNT  (INITIAL_DIVISOR)
    )
    pulse_counter
    (
        .clock          (clock),
        .clear          (1'b0),
        .up_down        (1'b1), // down
        .run            (run),
        .load           (load),
        .load_count     (load_count),
        .carry_in       (1'b0),
        // verilator lint_off PINCONNECTEMPTY
        .carry_out      (),
        // verilator lint_on PINCONNECTEMPTY
        .count          (count)
    );

// When an input pulse arrives at the same time as the output pulse, when the
// counter reloads, we have to count that input pulse. So we instead reload
// the counter with `divisor` minus 1. We generate that value here.

    wire [WORD_WIDTH-1:0] divisor_minus_one;

    Adder_Subtractor_Binary
    #(
        .WORD_WIDTH (WORD_WIDTH)
    )
    subtract_one
    (
        .add_sub    (1'b1),    // 0/1 -> A+B/A-B
        .carry_in   (1'b0),
        .A_in       (divisor),
        .B_in       (WORD_ONE),
        .sum_out    (divisor_minus_one),
        // verilator lint_off PINCONNECTEMPTY
        .carry_out  ()
        // verilator lint_on  PINCONNECTEMPTY
    );

// Finally, we implement the control logic for the above modules: decrement
// the counter one step for each cycle `pulses_in` is high, send out a pulse
// when the counter reaches zero (except for the initial one), reload the
// counter at zero or when forced to restart, and if an input pulse arrives
// while the counter reloads, count it by loading the `divisor` minus 1.

    reg division_done = 1'b0;

    always @(*) begin
        run             = (pulses_in     == 1'b1);
        division_done   = (count         == WORD_ZERO);
        pulse_out       = (division_done == 1'b1);
        load            = (division_done == 1'b1) || (restart      == 1'b1);
        load_count      = ((load         == 1'b1) && (run          == 1'b1)) ? divisor_minus_one : divisor;
    end

endmodule

