
//# Pulse Generator

// Converts a change in `level_in` (an edge) into a pulse lasting one clock
// cycle. **The input edge must be synchronous to the clock.** The pulse
// outputs are combinational: a given pulse is generated in the same cycle as
// the relevant change in signal level.

// A Pulse Generator can eliminate some simple FSMs by converting a condition
// of unknown length into a one-shot event (e.g.: updating a register only
// once when a signal changes for an unknown time). 

`default_nettype none

module Pulse_Generator
(
    input   wire    clock,
    input   wire    level_in,
    output  reg     pulse_posedge_out,
    output  reg     pulse_negedge_out,
    output  reg     pulse_anyedge_out
);

    initial begin
        pulse_posedge_out = 1'b0;
        pulse_negedge_out = 1'b0;
        pulse_anyedge_out = 1'b0;
    end

// Create a version of the input delayed by one cycle. 

    wire level_in_delayed;

    Register
    #(
        .WORD_WIDTH     (1),
        .RESET_VALUE    (1'b0)
    )
    delay
    (
        .clock          (clock),
        .clock_enable   (1'b1),
        .clear          (1'b0),
        .data_in        (level_in),
        .data_out       (level_in_delayed)
    );

// When the input changes before its delayed version, immediately raise the
// relevant output.  On the next clock cycle, the delayed version will arrive
// and the raised output will go back low.

    always @(*) begin
        pulse_posedge_out = (level_in          == 1'b1) && (level_in_delayed  == 1'b0);
        pulse_negedge_out = (level_in          == 1'b0) && (level_in_delayed  == 1'b1);
        pulse_anyedge_out = (pulse_posedge_out == 1'b1) || (pulse_negedge_out == 1'b1);
    end

endmodule

