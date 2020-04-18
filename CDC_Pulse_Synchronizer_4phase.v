
//# Clock Domain Crossing (CDC) Pulse Synchronizer (4-phase handshake)

// Reliably passes a synchronous posedge pulse from one clock domain to
// another when we don't know anything about the relative clock frequencies or
// the pulse duration. *Uses a 4-phase asynchronous handshake.*

// The recommended input is a single-cycle pulse in the sending clock domain.
// Adjust the output pulse length (in receiving clock cycles) with the
// RECV_PULSE_LENGTH parameter.

// <div class="bordered">

// Unless you *really* need to save a few gates, I would recommend you instead
// use the [2-phase handshake Pulse
// Synchronizer](./CDC_Pulse_Synchronizer_2phase.html), as it can accept input
// pulses at twice the maximum rate. This 4-phase implementation exists for
// comparison and education.

// </div>

//## Theory of Operation

// We can't simply use a [CDC Synchronizer](./CDC_Synchronizer.html) to pass
// a pulse of unknown duration between clock domains of unknown relation, as
// the receiving clock may not be able to sample the pulse correctly. So, we
// solve this by:

// * first latching the incoming pulse into a level signal,
// * synchronizing that level signal into the receiving clock domain,
// * using that synchronized level signal to generate a pulse, 
// * synchronizing that same level back into the sending clock domain,
// * using that synchronized level to clear the original level signal.

// This process then happens all over again with the cleared level signal,
// which does not generate a pulse in the receiving clock domain, until the
// system is back into its original rest state, ready to receive another input
// pulse. This process of raising a signal, waiting for a response to rise,
// then dropping the first signal, then waiting for the response to drop, is
// a 4-phase asynchronous handshake. It does not depends on the timing of the
// signals, only their sequence.

//## Input Pulse Frequency Limit

// The time taken for the 4-phase handshake to complete puts an upper limit on
// the input pulse rate, that also depends on the receiving clock frequency.
// If we exceed this rate, input pulses will be lost, as the input pulse latch
// will have not been cleared yet.

// At the upper limit, when the receiving clock frequency is fast enough to be
// "infinite" from the point of view of the sending clock (i.e.: the handshake
// response arrives soon enough within a single cycle of the sending clock to
// meet setup timing), then we only need to sum up the latencies on the sending
// clock side:

// 1. Latching (or clearing) the input pulse: 1 cycle
// 2. CDC into the receving clock domain: 0 cycles
// 3. CDC back into the sending clock domain: 3 cycles (worst case)
// 4. The input latch now clears, and the steps 1, 2, and 3 repeat.

// Thus there must be *at an absolute minimum* 8 idle sending clock cycles
// between input pulses, or one input pulse every 9th sending clock cycle.
// (We can't overlap the clearing and latching, since clear has priority over
// input data in a [Register](./Register.html).) Fortunately, we don't have to
// compute inter-pulse delays for every possible sending to receiving clock
// frequency ratio a system will encounter. We can instead signal `ready` on
// the sending side by noting when both the initial sending level and the
// returned response are low, denoting a system at rest ready for the next
// 4-phase handshake.

`default_nettype none

module CDC_Pulse_Synchronizer_4phase
#(
    parameter RECV_PULSE_LENGTH = 1, // 1 or greater
    parameter CDC_EXTRA_DEPTH   = 0  // 0 or greater, if necessary
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

    initial begin
        sending_ready = 1'b0;
    end

// Capture the sending pulse into a level, and clear the latch once the level
// has passed into and returned from the receiving clock domain *and the
// sending pulse has ended*. This gating prevents a cycle of latch set/reset
// if the sending pulse is longer than the round-trip latency of level signal
// to and back from the receiving clock domain, causing a train of pulses in
// the receiving clock domain. A local clear overrides all this.

    wire sending_level;
    reg  clear_sending = 1'b0;
    wire level_response;

    always @(*) begin
        clear_sending = (level_response == 1'b1) && (sending_pulse_in == 1'b0);
        clear_sending = (clear_sending  == 1'b1) || (sending_clear    == 1'b1);
    end

    Pulse_Latch
    #(
        .RESET_VALUE (1'b0)
    )
    sending_pulse_capture
    (
        .clock          (sending_clock),
        .clear          (clear_sending),
        .pulse_in       (sending_pulse_in),
        .level_out      (sending_level)
    );

// Pass the latched sending pulse to the receiving clock domain

    wire receiving_level;

    CDC_Synchronizer
    #(
        .EXTRA_DEPTH        (CDC_EXTRA_DEPTH)
    )
    to_receiving
    (
        .receiving_clock    (receiving_clock),
        .bit_in             (sending_level),
        .bit_out            (receiving_level)
    );

// Now pass the synchronized level back to the sending clock domain to
// signal that the CDC is complete and to clear the latch.

    CDC_Synchronizer
    #(
        .EXTRA_DEPTH        (CDC_EXTRA_DEPTH)
    )
    to_sending
    (
        .receiving_clock    (sending_clock),
        .bit_in             (receiving_level),
        .bit_out            (level_response)
    );

// In parallel to all of the above, signal when both the sending level and the
// returned level from the receiving clock domain are low, indicating
// readiness for the next 4-phase handshake. *An input pulse sent while ready
// is low will be lost.*

    always @(*) begin
        sending_ready = (sending_level == 1'b0) && (level_response == 1'b0);
    end

// Finally, convert the receiving level to a pulse in the receiving clock domain

    Pulse_Generator
    #(
        .PULSE_LENGTH   (RECV_PULSE_LENGTH),
        .EDGE_TYPE      ("POS")
    )
    receiving_level_to_pulse
    (
        .clock          (receiving_clock),
        .clock_enable   (1'b1),
        .clear          (receiving_clear),
        .level_in       (receiving_level),
        .pulse_out      (receiving_pulse_out)
    );

endmodule

