
//# Pulse Divider

// Outputs a single-cycle high pulse when `divisor` input pulses have been
// received, thus dividing their number. For example, if `divisor` is 3,
// then:

// * 9 input pulses will produce 3 output pulses
// * 5 input pulses will produce 1 output pulse
// * 7 input pulses will produce 2 output pulses

// Pulses do not have to be distinct: holding the input high for a number of
// clock cycles will have the same effect as the same number of separate,
// single-cycle pulses.

// The output pulse occurs in the same cycle as the input pulse, which means
// there is a combinational path from `pulses_in` to `pulse_out`. This is
// necessary to avoid a cycle of latency between an input pulse arriving and
// signalling that it is a multiple of `divisor`. (e.g. signalling that the
// current load fills the last empty space in a buffer).

// The `divisor` is reloaded automatically after each output pulse. Any
// changes to the `divisor` input before then do not affect the current pulse
// division. However, asserting `restart` for one cycle will force the
// `divisor` to reload and the pulse division to restart. Holding `restart`
// high will halt the pulse divider. A `restart` pulse is not required after
// startup.

// *Loading a `divisor` of zero will disable the output pulses, raises
// `div_by_zero`, and will load `divisor` every cycle until it becomes
// non-zero.* 

//## Uses

// * Signal when a number of events have happened (e.g.: counting loads into
// a pipeline or buffer)
// * Generate a periodic enable pulse derived from your main clock. (tie
// `pulses_in` to 1)
// * Perform integer division: the number of output pulses after your input
// pulses are done is the quotient, the number of input pulses you have to then
// provide to get one more output pulse is the remainder if less than
// `divisor`, else it's zero (i.e.: it's the remainder modulo `divisor`).

`default_nettype none

module Pulse_Divider
#(
    parameter                   WORD_WIDTH      = 0,
    parameter [WORD_WIDTH-1:0]  INITIAL_DIVISOR = 0
)
(
    input  wire                     clock,
    input  wire                     restart,
    input  wire [WORD_WIDTH-1:0]    divisor,
    input  wire                     pulses_in,
    output reg                      pulse_out,
    output reg                      div_by_zero
);

    initial begin
        pulse_out   = 1'b0;
        div_by_zero = 1'b0;
    end

// These are the two counter values which are important: WORD_ONE signifies we
// have received `divisor` or `INITIAL_DIVISOR` pulses, and WORD_ZERO is never
// reached unless a division by zero is attempted by loading or initializing
// with a value of zero.

    localparam WORD_ZERO = {WORD_WIDTH{1'b0}};
    localparam WORD_ONE  = {{WORD_WIDTH-1{1'b0}}, 1'b1};

// The core of the pulse divider is a simple down counter whose value is
// interpreted as "input pulses remaining before an output pulse". So a loaded
// `divisor` of 3 would accept 3 input pulses to count "3, 2, 1", at which
// point `pulse_out` goes high on the third `pulses_in` while the counter is
// at `1`, the counter reloads the divisor, and everything returns to
// start conditions at the next clock edge. *The count of zero is never
// reached by counting.*

    reg                     run     = 1'b0;
    reg                     load    = 1'b0;
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
        .load_count     (divisor),
        .carry_in       (1'b0),
        // verilator lint_off PINCONNECTEMPTY
        .carry_out      (),
        // verilator lint_on PINCONNECTEMPTY
        .count          (count)
    );

// Finally, we implement the control logic. We split out the calculation of
// `div_by_zero` into a parallel procedural block, otherwise the linter could
// see a false combinational loop between `div_by_zero` and `pulse_out` when
// the divider is used in an enclosing module, since it cannot see into the
// module hierarchy (I'm not certain of this).

    always @(*) begin
        div_by_zero = (count == WORD_ZERO);
    end

    reg division_done = 1'b0;

    always @(*) begin
        run             = (pulses_in     == 1'b1) && (count     != WORD_ZERO);
        division_done   = (pulses_in     == 1'b1) && (count     == WORD_ONE);
        load            = (division_done == 1'b1) || (restart   == 1'b1) || (div_by_zero == 1'b1);
        pulse_out       = (division_done == 1'b1) && (restart   == 1'b0);
    end

endmodule

