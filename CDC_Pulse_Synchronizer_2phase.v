
//# Clock Domain Crossing (CDC) Pulse Synchronizer (2-phase handshake)

// Reliably passes a synchronous posedge pulse from one clock domain to
// another when we don't know anything about the relative clock frequencies or
// the pulse duration. *Uses a 2-phase asynchronous handshake.*

// The recommended input is a single-cycle pulse in the sending clock domain.
// Adjust the output pulse length (in receiving clock cycles) with the
// RECV_PULSE_LENGTH parameter.

// <div class="bordered">

// For comparison, have a look at the [4-phase handshake Pulse
// Synchronizer](./CDC_Pulse_Synchronizer_4phase.html). It has slightly
// simpler hardware, but a more complex handshake leading to double the
// latency across clock domains, so it can only accept input pulses at half
// the maximum rate of this 2-phase implementation. 

// </div>

//## Theory of Operation

// We can't simply use a [CDC Synchronizer](./CDC_Synchronizer.html) to pass
// a pulse of unknown duration between clock domains of unknown relation, as
// the receiving clock may not be able to sample the pulse correctly. So, we
// solve this by:

// * first using the incoming pulse to toggle a register and disable
// further toggles,
// * synchronizing the output of that toggle register into the receiving clock domain,
// * using that synchronized toggle signal to generate a pulse (on any toggle
// edge) in the receiving clock domain,
// * synchronizing that toggle signal back into the sending clock domain,
// * using that synchronized toggle signal to re-enable the toggle register

// Once the initial signal and its response both reach the same value, the
// system is back into one of its two rest states, ready to receive another
// input pulse. This process of toggling a signal, then waiting for the
// response to also toggle into the same state, is a 2-phase asynchronous
// handshake. It does not depend on the timing of the signals, only their
// sequence.

//## Input Pulse Frequency Limit

// The time taken for the 2-phase handshake to complete puts an upper limit on
// the input pulse rate, that also depends on the receiving clock frequency.
// If we exceed this rate, input pulses will be lost, as the input toggle
// register will have not been re-enabled yet.

// At the upper limit, when the receiving clock frequency is fast enough to be
// "infinite" from the point of view of the sending clock (i.e.: the handshake
// response arrives soon enough within a single cycle of the sending clock to
// meet setup timing), then we only need to sum up the latencies on the sending
// clock side:

// 1. Toggling the input register (and disabling it): 1 cycle
// 2. CDC into the receving clock domain: 0 cycles
// 3. CDC back into the sending clock domain: 3 cycles (worst case)
// 4. The input toggle register is now re-enabled and can receive a new input
// pulse..

// Since re-enabling the toggle register and receiving an input pulse can
// happen in the same cycle, there must be *at an absolute minimum* 3 idle
// sending clock cycles between input pulses, or one input pulse every 4th
// sending clock cycle.  Fortunately, we don't have to compute inter-pulse
// delays for every possible sending to receiving clock frequency ratio
// a system will encounter. The toggle register enabling logic also acts as
// a `ready` output on the sending side by noting when both the initial
// sending level and the returned response are at the same value, denoting
// a system at rest ready for the next 2-phase handshake.

`default_nettype none

module CDC_Pulse_Synchronizer_2phase
#(
    parameter RECV_PULSE_LENGTH = 1, // 1 or greater
    parameter CDC_EXTRA_DEPTH   = 0
)
(
    input   wire    sending_clock,
    input   wire    sending_clear,
    input   wire    sending_pulse_in,
    output  reg     sending_ready,

    input   wire    receiving_clock,
    input   wire    receiving_clear,
    output  wire    receiving_pulse_out
);

// Cleanup the input pulse to a single cycle pulse, so we cannot have
// a situation where the 2-phase handshake has completed and a long input pulse
// is still high, causing a second toggle and thus a second pulse in the
// receiving clock domain.

// NOTE: It's possible to replace the Pulse_Generator with a a couple of AND
// and NOT gates, but this saves no logic (only a register), and makes this
// part of the design much harder to understand.

    wire cleaned_pulse_in;

    Pulse_Generator
    #(
        .PULSE_LENGTH   (1),
        .EDGE_TYPE      ("POS")
    )
    pulse_cleaner
    (
        .clock          (sending_clock),
        .clock_enable   (1'b1),
        .clear          (sending_clear),
        .level_in       (sending_pulse_in),
        .pulse_out      (cleaned_pulse_in)
    );

// Now use that single-cycle pulse to toggle a register, signalling the start
// of a 2-phase asynchronous handshake. We feed the output back to the input
// to keep the register output static when not toggling.

// NOTE: `clear` cannot be used here: if the toggle register happens to have
// a high output, and we clear it, this will start a spurious 2-phase
// handshake and generate a spurious pulse in the receiving clock domain. Even
// if we could guarantee that the logic in both the sending and receiving
// clock domains would be cleared together, we can't be sure when each clear
// will take effect, and so the spurious pulse could have side-effects.

    wire toggle_response;
    reg  enable_toggle = 1'b0;
    wire sending_toggle;

    Register_Toggle
    #(
        .WORD_WIDTH     (1),
        .RESET_VALUE    (1'b0)
    )
    start_handshake
    (
        .clock          (sending_clock),
        .clock_enable   (enable_toggle),
        .clear          (1'b0),
        .toggle         (cleaned_pulse_in),
        .data_in        (sending_toggle),
        .data_out       (sending_toggle)
    );

// When the toggle and its response have the same value, the 2-phase handshake
// is complete and we are ready to toggle again.

    always @(*) begin
        enable_toggle = (sending_toggle == toggle_response);
        sending_ready = enable_toggle;
    end

// Pass the toggle signal to the receiving clock domain

    wire receiving_toggle;

    CDC_Synchronizer
    #(
        .EXTRA_DEPTH        (CDC_EXTRA_DEPTH)
    )
    to_receiving
    (
        .receiving_clock    (receiving_clock),
        .bit_in             (sending_toggle),
        .bit_out            (receiving_toggle)
    );

// Now pass the synchronized toggle signal back to the sending clock domain to
// signal that the CDC is complete and to re-enable the toggle register.

    CDC_Synchronizer
    #(
        .EXTRA_DEPTH        (CDC_EXTRA_DEPTH)
    )
    to_sending
    (
        .receiving_clock    (sending_clock),
        .bit_in             (receiving_toggle),
        .bit_out            (toggle_response)
    );

// Finally, convert the receiving toggle to a pulse in the receiving clock domain.
// We generate an output pulse on either of the toggle transitions.

    Pulse_Generator
    #(
        .PULSE_LENGTH   (RECV_PULSE_LENGTH),
        .EDGE_TYPE      ("ANY")
    )
    receiving_toggle_to_pulse
    (
        .clock          (receiving_clock),
        .clock_enable   (1'b1),
        .clear          (receiving_clear),
        .level_in       (receiving_toggle),
        .pulse_out      (receiving_pulse_out)
    );

endmodule

