//# Pulse Gate

// Gates sychronous pulses without truncating them.

// Raising `gate_pulses` will block `pulses_in` from passing through to
// `pulses_out`, and dropping `gate_pulses` will let pulses through. However,
// *changes to `gate_pulses` only take effect at the start of the inactive
// period of pulses*, as defined by the `PULSE_ACTIVE_LEVEL` parameter. The
// change in `gate_pulses` has taken effect when the level of `gate_state`
// changes to match.

// Dropping `clock_enable` causes `gate_pulses` to be ignored and the gate
// remains in its current state. Raising `clear` forcibly opens the gate,
// *which may let a runt pulse through*.

//## Uses

// When a circuit generates pulses of a specific duration, it is usually for
// a functional reason, so we don't want to accidentally shorten the pulses.
// For example, the pulse duration may encode the framing of serial data or
// the Pulse-Width Modulation (PWM) of an analog value.

`default_nettype none

module Pulse_Gate
#(
    parameter PULSE_ACTIVE_LEVEL = 1'bX // Passes linting, but not simulation!
)
(
    input   wire    clock,
    input   wire    clock_enable,
    input   wire    clear,

    input   wire    pulses_in,
    input   wire    gate_pulses,
    output  wire    gate_state,
    output  reg     pulses_out
);

    localparam GATE_OPEN        = 1'b0;
    localparam PULSE_INACTIVE   = ~PULSE_ACTIVE_LEVEL;

    initial begin
       pulses_out = PULSE_INACTIVE;
    end

// The `gate` remains open or closed until we toggle its state.

    reg gate_toggle = 1'b0;

    Register_Toggle
    #(
        .WORD_WIDTH     (1),
        .RESET_VALUE    (GATE_OPEN)
    )
    gate
    (
        .clock          (clock),
        .clock_enable   (clock_enable),
        .clear          (clear),
        .toggle         (gate_toggle),
        .data_in        (gate_state),
        .data_out       (gate_state)
    );

// Let the pulses pass if the gate is open, else output the inactive pulse
// state. Make the `gate_state` match the `gate_pulses` input once `pulses_in`
// goes inactive.

    always @(*) begin
        pulses_out  = (gate_state == GATE_OPEN) ? pulses_in : PULSE_INACTIVE;
        gate_toggle = (pulses_in  == PULSE_INACTIVE) && (gate_state != gate_pulses);
    end

endmodule

