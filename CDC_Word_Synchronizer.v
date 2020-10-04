//# CDC Word Synchronizer

// Synchronizes the transfer of a word of data from one clock domain to
// another, regardless of relative clock frequencies. Uses ready/valid
// handshakes at the sending and receiving ends, but these can be
// short-circuited for continuous transfers without backpressure: ignore
// `sending_ready` and tie `receiving_ready` high. Add
// `EXTRA_CDC_DEPTH` if you are running near the limits of your silicon
// (consult your vendor datasheets regarding metastability).

// The code is laid out in transfer order: we start at the sending handshake,
// convert a signal for new valid data into a level, which passes through CDC
// into the receiving clock domain and completes the receiving handshake. Once
// the receiving handshake completes, we convert that event into a level,
// which passes through CDC back into the sending clock domain to start a new
// sending handshake if there is more data to send.

// This module is closely related to the [2-phase Pulse
// Synchronizer](./CDC_Pulse_Synchronizer_2phase.html).

//## Operating Notes

// * When a sending handshake completes, `sending_data` is latched into
// a register, so you can sample synchronously changing inputs without
// problems.
// * If a reset happens, you must assert both `sending_clear` and
// `receiving_clear` with a (preferably) synchronous reset signal long enough
// to let any level toggle pass through CDC and reach its destination toggle
// register. *This takes 3 cycles in both `sending_clock` and
// `receiving_clock`.*
// * Set `OUTPUT_BUFFER_TYPE` to match the desired behaviour at the output of
// the receiving handshake:
//     * '"HALF"': Uses a [Pipeline Half Buffer](./Pipeline_Half_Buffer.html),
//     and will not start the next sending handshake until the receiving handshake
//     completes. Use this when sampling a changing signal (e.g.: a counter) or
//     to force the processing rate of the sender to match that of the receiver.
//     * '"SKID"': Uses a [Pipeline Skid Buffer](./Pipeline_Skid_Buffer.html),
//     which allows the next sending handshake to start before the receiving
//     handshake completes. If the transfer from the next sending handshake
//     arrives before the first receiving handshake completes, then further
//     sending handshakes are blocked until the first receiving handshake
//     completes. Use this to allow both ends to send/receive data concurrently.
//     * '"FIFO"': Uses a [Pipeline FIFO Buffer](./Pipeline_FIFO_Buffer.html),
//     which allows `FIFO_BUFFER_DEPTH` sending handshakes to complete before
//     blocking. Use this if the downstream pipeline takes in data in bursts.
//     The value of `FIFO_BUFFER_RAMSTYLE` will depend on your device, CAD tool,
//     FIFO depth/width, etc...

//## Latency and Throughput

// The absolute latency from sending to receiving handshake depends on the
// relative sending and receiving clock frequencies, but we can count the
// cycles, in order:

// * 1 sending cycle to transform the completion of a sending handshake to a level toggle
// * 1**\*** to 3 receiving cycles to do the CDC into the receiving clock domain (and maybe complete a receiving handshake)
// * 1 receiving cycle to transform the completion of the receiving handshake to a level toggle
// * 1**\*** to 3 sending cycles to do the CDC into the sending clock domain (and maybe complete a sending handshake)

// <div class="bordered">
// **\*Corner Case:** The situations where the CDC transfers take 1 cycle in
// either direction are mutually exclusive. The timing of the
// sending/receiving clock edges that makes a CDC crossing in one direction
// take one cycle, is naturally reversed when crossing in the other direction,
// and so cannot happen, and takes the more common 2 to 3 cycles. See the
// "Latency" section in [A Primer on Clock Domain Crossing (CDC)
// Theory](./cdc.html) for details. **Unless you know your clocks are
// plesiochronous, it is safer and simpler to ignore this corner case and
// assume 2 to 3 cycles per CDC.** However, we still account for this case 
// in the latency ranges that follow. 
// </div>

// Thus, given roughly equal sending and receiving clock rates, a complete
// transfer takes between 5 and 8 sending clock cycles. If the receiving clock
// rate is effectively "infinite", allowing for the whole receiving side to
// finish within a single sending clock cycle, a complete transfer takes 2 to
// 4 sending cycles.  If the sending clock rate is similarly effectively
// "infinite" relative to the receiving clock rate, a transfer takes 2 to
// 4 receiving clock cycles.

// Thus, we can calculate the time for a single transfer as 2 to 4 times the
// sending clock period plus 2 to 4 times the receiving clock period. The
// inverse of that is, of course, the number of transfers per unit time.

//## Parameters, Ports, and Constants

`default_nettype none

module CDC_Word_Synchronizer
#(
    parameter WORD_WIDTH            = 0,
    parameter EXTRA_CDC_DEPTH       = 0,
    parameter OUTPUT_BUFFER_TYPE    = "", // "HALF", "SKID", "FIFO"
    parameter FIFO_BUFFER_DEPTH     = 0,  // Only for "FIFO"
    parameter FIFO_BUFFER_RAMSTYLE  = ""  // Only for "FIFO"
)
(
    input   wire                        sending_clock,
    input   wire                        sending_clear,
    input   wire    [WORD_WIDTH-1:0]    sending_data,
    input   wire                        sending_valid,
    output  wire                        sending_ready,

    input   wire                        receiving_clock,
    input   wire                        receiving_clear,
    output  wire    [WORD_WIDTH-1:0]    receiving_data, 
    output  wire                        receiving_valid,
    input   wire                        receiving_ready
);

    localparam WORD_ZERO = {WORD_WIDTH{1'b0}};

//## From the Sending Handshake

// First, handle the sending handshake. Signal when it completes and we have
// a data word to latch, then wait until we can accept the next word.

    wire [WORD_WIDTH-1:0]   sending_handshake_data;
    wire                    sending_handshake_complete;
    wire                    accept_next_word;

    Pipeline_to_Pulse
    #(
        .WORD_WIDTH             (WORD_WIDTH)
    )
    sending_handshake
    (
        .clock                  (sending_clock),
        .clear                  (sending_clear),

        // Pipeline input
        .valid_in               (sending_valid),
        .ready_in               (sending_ready),
        .data_in                (sending_data),

        // Pulse interface to connected module input
        .module_data_in         (sending_handshake_data),
        .module_data_in_valid   (sending_handshake_complete),

        // Signal that the module can accept the next input
        .module_ready           (accept_next_word)
    );

// Then latch the data when the sending handshake completes.

    wire [WORD_WIDTH-1:0]   sending_handshake_data_latched;

    Register
    #(
        .WORD_WIDTH     (WORD_WIDTH),
        .RESET_VALUE    (WORD_ZERO)
    )
    sending_data_storage
    (
        .clock          (sending_clock),
        .clock_enable   (sending_handshake_complete),
        .clear          (sending_clear),
        .data_in        (sending_handshake_data),
        .data_out       (sending_handshake_data_latched)
    );

// Convert the completion of the sending handshake into a level toggle, which
// initiates a 2-phase asynchronous handshake. This level does not toggle
// again until the completion of the next sending handshake, which since it
// can only happen after the receiving handshake completes, guarantees the
// level stays constant long enough to pass through CDC, regardless of
// relative clock frequency.

    wire sending_handshake_toggle;

    Register_Toggle
    #(
        .WORD_WIDTH     (1),
        .RESET_VALUE    (1'b0)
    )
    start_async_handshake
    (
        .clock          (sending_clock),
        .clock_enable   (1'b1),
        .clear          (sending_clear),
        .toggle         (sending_handshake_complete),
        .data_in        (sending_handshake_toggle),
        .data_out       (sending_handshake_toggle)
    );

// Then we synchronize the start of the 2-phase asynchronous handshake into
// the receiving clock domain.

    wire sending_handshake_synced;

    CDC_Bit_Synchronizer
    #(
        .EXTRA_DEPTH        (EXTRA_CDC_DEPTH)  // Must be 0 or greater
    )
    into_receiving
    (
        .receiving_clock    (receiving_clock),
        .bit_in             (sending_handshake_toggle),
        .bit_out            (sending_handshake_synced)
    );

//## To the Receiving Handshake

// Once in the receiving clock domain, we convert any toggle in level into
// a pulse, which signals new data is available.

    wire sending_handshake_data_latched_valid;

    Pulse_Generator
    convert_async_handshake_sending
    (
        .clock              (receiving_clock),
        .level_in           (sending_handshake_synced),
        // verilator lint_off PINCONNECTEMPTY
        .pulse_posedge_out  (),
        .pulse_negedge_out  (),
        // verilator lint_on  PINCONNECTEMPTY
        .pulse_anyedge_out  (sending_handshake_data_latched_valid)
    );

// Then we handle the receiving handshake, which is buffered in one of
// multiple ways (see *Operating Notes*) for different applications.

    wire receiving_handshake_complete;

    Pulse_to_Pipeline
    #(
        .WORD_WIDTH             (WORD_WIDTH),
        .OUTPUT_BUFFER_TYPE     (OUTPUT_BUFFER_TYPE),  // "HALF", "SKID", "FIFO"
        .FIFO_BUFFER_DEPTH      (FIFO_BUFFER_DEPTH),   // Only for "FIFO"
        .FIFO_BUFFER_RAMSTYLE   (FIFO_BUFFER_RAMSTYLE) // Only for "FIFO"
    )
    receiving_handshake
    (
        .clock                  (receiving_clock),
        .clear                  (receiving_clear),

        // Pipeline output
        .valid_out              (receiving_valid),
        .ready_out              (receiving_ready),
        .data_out               (receiving_data),

        // Pulse interface from connected module
        .module_data_out        (sending_handshake_data_latched),
        .module_data_out_valid  (sending_handshake_data_latched_valid),

        // Signal that the module can accept the next input
        .module_ready           (receiving_handshake_complete)
    );

// We then convert the completion of the receiving handshake into a level
// toggle back into the sending clock domain to complete the 2-phase
// handshake. This level does not toggle again until the completion of the
// next receiving handshake, which since it can only happen after the next
// sending handshake completes, guarantees the level stays constant long
// enough to pass through CDC.

    wire receiving_handshake_toggle;

    Register_Toggle
    #(
        .WORD_WIDTH     (1),
        .RESET_VALUE    (1'b0)
    )
    finish_async_handshake
    (
        .clock          (receiving_clock),
        .clock_enable   (1'b1),
        .clear          (receiving_clear),
        .toggle         (receiving_handshake_complete),
        .data_in        (receiving_handshake_toggle),
        .data_out       (receiving_handshake_toggle)
    );

// Then we synchronize the end of the 2-phase handshake into the sending clock
// domain.

    wire receiving_handshake_synced;

    CDC_Bit_Synchronizer
    #(
        .EXTRA_DEPTH        (EXTRA_CDC_DEPTH)  // Must be 0 or greater
    )
    into_sending
    (
        .receiving_clock    (sending_clock),
        .bit_in             (receiving_handshake_toggle),
        .bit_out            (receiving_handshake_synced)
    );

//## And Back to the Sending Handshake

// Finally, convert the synchronized receiving handshake completion into
// a pulse to start or complete the next sending handshake.

    Pulse_Generator
    convert_async_handshake_receiving
    (
        .clock              (sending_clock),
        .level_in           (receiving_handshake_synced),
        // verilator lint_off PINCONNECTEMPTY
        .pulse_posedge_out  (),
        .pulse_negedge_out  (),
        // verilator lint_on  PINCONNECTEMPTY
        .pulse_anyedge_out  (accept_next_word)
    );

endmodule

