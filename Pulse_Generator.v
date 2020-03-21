
//# Pulse Generator

// Converts a change in signal level (an edge) into a high pulse lasting a set
// number of clock cycles, usually 1. This device can eliminate some simple
// FSMs by converting a condition of unknown length into a one-shot event
// (e.g.: updating a register only once).

// The detected edge type (positive, negative, any) is set by a parameter, as
// is the length of the output pulse. **The input edge must be synchronous to
// the clock.**

// If the output pulse is longer than 1 clock cycle, raising `clear` will end
// the pulse at the end of the current clock cycle. Holding `clear` high will
// prevent output pulses.

// `clock_enable` must be high for the input edge to be detected, and if
// `clock_enable` is dropped during the output pulse, the pulse will remain
// high until `clock_enable` is reasserted, and then the pulse will continue
// until the expected remaining number of pulse high clock cycles have passed.

`default_nettype none

module Pulse_Generator
#(
    parameter PULSE_LENGTH  = 0, // Minimum 1, or greater
    parameter EDGE_TYPE     = "" // POS, NEG, ANY
)
(
    input   wire    clock,
    input   wire    clock_enable,
    input   wire    clear,
    input   wire    level_in,
    output  reg     pulse_out
);

    localparam PIPE_ZERO = {PULSE_LENGTH{1'b0}};

    initial begin
        pulse_out = 1'b0;
    end

// Create a delayed version of the input. The length of the delay, in clock
// cycles, becomes the length of the pulse when the input edge arrives.

    wire level_in_delayed;

    Register_Pipeline
    #(
        .WORD_WIDTH     (1),
        .PIPE_DEPTH     (PULSE_LENGTH),
        .RESET_VALUES   (PIPE_ZERO)
    )
    Delay_Line
    (
        .clock          (clock),
        .clock_enable   (clock_enable),
        .clear          (clear),
        .parallel_load  (1'b0),
        .parallel_in    (PIPE_ZERO),
        // verilator lint_off PINCONNECTEMPTY
        .parallel_out   (),
        // verilator lint_on  PINCONNECTEMPTY
        .pipe_in        (level_in),
        .pipe_out       (level_in_delayed)
    );

// When the input changes before its delayed version, raise the output.
// Eventually, the delayed version will arrive and the output will go low.

    generate
        if (EDGE_TYPE == "POS") begin
            always @(*) begin
                pulse_out = (level_in == 1'b1) && (level_in_delayed == 1'b0);
            end
        end

        if (EDGE_TYPE == "NEG") begin
            always @(*) begin
                pulse_out = (level_in == 1'b0) && (level_in_delayed == 1'b1);
            end
        end

        if (EDGE_TYPE == "ANY") begin
            always @(*) begin
                pulse_out = (level_in != level_in_delayed);
            end
        end
    endgenerate

endmodule

