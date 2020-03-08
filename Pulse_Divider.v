
//# Pulse Divider

// Outputs a single-cycle high pulse when PULSE_COUNT input pulses have been
// received, thus dividing their number. For example, if PULSE_COUNT is 3,
// then:

// * 9 input pulses will produce 3 output pulses
// * 5 input pulses will produce 1 output pulse
// * 7 input pulses will produce 2 output pulses

// Pulses do not have to be separate: holding the input high for the expected
// number of clock cycles will have the same effect as the same number of
// intermittent pulses. Asserting clear will restart the pulse division as if
// no pulse had ever been received.

// This module has many uses:

// * Signal when a number of events have happened.
// * Generate a periodic enable pulse derived from your main clock. (tie
// pulses_in to 1)
// * Perform integer division: the number of output pulses after your input
// pulses are done is the quotient, the number of input pulses you have to then
// provide to get one more output pulse is the remainder if less than
// PULSE_COUNT, else it's zero (i.e.: it's the remainder modulo PULSE_COUNT).

`default_nettype none

module Pulse_Divider
#(
    parameter PULSE_COUNT = 3
)
(
    input  wire clock,
    input  wire clear,
    input  wire pulses_in,
    output reg  pulse_out
);

    initial begin
        pulse_out = 1'b0;
    end

    `include "clog2_function.vh"

    localparam WORD_WIDTH   = clog2(PULSE_COUNT+1);
    localparam WORD_ZERO    = {WORD_WIDTH{1'b0}};
    localparam WORD_ONE     = {{WORD_WIDTH-1{1'b0}}, 1'b1};

    reg                     run         = 1'b0;
    reg                     load        = 1'b0;
    reg  [WORD_WIDTH-1:0]   load_count  = WORD_ZERO;
    wire [WORD_WIDTH-1:0]   count;

    Counter_Binary
    #(
        .WORD_WIDTH     (WORD_WIDTH),
        .INCREMENT      (WORD_ONE),
        .INITIAL_COUNT  (PULSE_COUNT)
    )
    pulse_counter
    (
        .clock          (clock),
        .clear          (clear),
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

    always @(*) begin
        run         = (pulses_in == 1'b1);
        load        = (count     == WORD_ZERO);
        load_count  = ((load == 1'b1) && (run == 1'b1)) ? PULSE_COUNT-1 : PULSE_COUNT;
    end

endmodule

