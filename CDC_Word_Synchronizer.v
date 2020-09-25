//# CDC Word Synchronizer

// Synchronizes the transfer of a word of data from one clock domain to
// another, regardless of relative clock frequencies. Uses ready/valid
// handshakes at the sending and receiving ends, but these can be
// short-circuited for continuous transfers without backpressure: ignore
// `sending_data_ready` and tie `receiving_data_ready` high. Add `EXTRA_DEPTH`
// if you are running near the limits of your silicon (consult your
// vendor datasheets regarding metastability).

// The code is laid out in transfer order: we start at the sending handshake,
// convert a signal for new valid data into a level, which passes through CDC
// into the receiving clock domain and begins the receiving ready/valid
// handshake. Once the receiving handshake completes, we convert that event
// into a level, which passes through CDC back into the sending clock domain
// to complete the sending handshake and start a new handshake if there is
// more data to send.

// This module is closely related to the [2-phase Pulse
// Synchronizer](./CDC_Pulse_Synchronizer_2phase.html).

//## Operating Conditions

// This module depends on a few critical conditions:

// * Once `sending_data_valid` is asserted, it stays constant until the
// sending ready/valid handshake completes.
// * While `sending_data_valid` is asserted, `sending_data` stays constant
// until the sending ready/valid handshake completes.
// * If a reset happens, you must assert both `sending_clear` and
// `receiving_clear` with a synchronous reset signal long enough to let any
// level toggle pass through CDC and reach its destination latch or toggle
// register. *This takes 3 cycles in both `sending_clock` and
// `receiving_clock`.*

//## Latency and Throughput

// The absolute latency depends on the relative clock frequencies, but we can
// count the cycles, in order:

// * 1 sending cycle to transform the start of a sending handshake to a level
// * 2 to 3 cycles to do the CDC into the receiving clock domain
// * 1 receiving cycle to begin the receiving handshake
// * 1 receiving cycle to transform the end of the receiving handshake to a level
// * 2 to 3 cycles to do the CDC into the sending clock domain (which also ends the sending handshake)

// Thus, given roughly equal sending and receiving clock rates, a complete
// transfer takes between 7 and 9 sending clock cycles. If the receiving clock
// rate is effectively "infinite", allowing for the whole receiving side to
// finish within a single sending clock cycle, a complete transfer takes 3 to
// 4 sending cycles.  If the sending clock rate is similarly effectively
// "infinite" relative to the receiving clock rate, a transfer takes 4 to
// 5 receiving clock cycles.

// Thus, we can calculate the time for a single transfer as 3 to 4 times the
// sending clock period plus 4 to 5 times the receiving clock period. The
// inverse of that is, of course, the number of transfers per unit time.

//## Interfaces and Data Pass-Through

`default_nettype none

module CDC_Word_Synchronizer
#(
    parameter WORD_WIDTH    = 0,
    parameter EXTRA_DEPTH   = 0
)
(
    input   wire                        sending_clock,
    input   wire                        sending_clear,
    input   wire    [WORD_WIDTH-1:0]    sending_data,
    input   wire                        sending_data_valid,
    output  wire                        sending_data_ready,

    input   wire                        receiving_clock,
    input   wire                        receiving_clear,
    output  reg     [WORD_WIDTH-1:0]    receiving_data, 
    output  wire                        receiving_data_valid,
    input   wire                        receiving_data_ready
);

    localparam WORD_ZERO = {WORD_WIDTH{1'b0}};

    initial begin
        receiving_data = WORD_ZERO;
    end

// The data is a direct pass-through, which **MUST** be held steady until both
// the sending and receiving handshaked complete. You may also have to guide
// your CAD tool to limit the maximum delay on these signals.

    always @(*) begin
        receiving_data = sending_data;
    end

//## Sending Handshake Start

// First, we express the completion of a transfer when `sending_data_ready` is
// asserted *for one cycle*, which then gates `sending_data_valid` for one
// cycle. Then, if there is no further data to transfer, `sending_data_valid`
// will stay low, else it will re-assert itself in the next cycle, and this
// rising edge will start another sending handshake.

    reg  sending_data_valid_gated = 1'b0;

    always @(*) begin
        sending_data_valid_gated = (sending_data_valid == 1'b1) && (sending_data_ready == 1'b0); 
    end

    wire sending_start_pulse;

    Pulse_Generator
    start_sending
    (
        .clock              (sending_clock),
        .level_in           (sending_data_valid_gated),
        .pulse_posedge_out  (sending_start_pulse),
        // verilator lint_off PINCONNECTEMPTY
        .pulse_negedge_out  (),
        .pulse_anyedge_out  ()
        // verilator lint_on  PINCONNECTEMPTY
    );

// Convert the sending start pulse into a level toggle, which initiates
// a 2-phase handshake. This level does not toggle again until the start of
// the next sending handshake, which since it can only happen after the
// receiving handshake completes, guarantees the level stays constant long
// enough to pass through the [CDC Synchronizer](./CDC_Bit_Synchronizer.html).

    wire sending_start_level;

    Register_Toggle
    #(
        .WORD_WIDTH     (1),
        .RESET_VALUE    (1'b0)
    )
    start_handshake
    (
        .clock          (sending_clock),
        .clock_enable   (1'b1),
        .clear          (sending_clear),
        .toggle         (sending_start_pulse),
        .data_in        (sending_start_level),
        .data_out       (sending_start_level)
    );

// Then we synchronize the start of the 2-phase handshake into the receiving
// clock domain.

    wire sending_start_level_synced;

    CDC_Bit_Synchronizer
    #(
        .EXTRA_DEPTH        (EXTRA_DEPTH)  // Must be 0 or greater
    )
    into_receiving
    (
        .receiving_clock    (receiving_clock),
        .bit_in             (sending_start_level),
        .bit_out            (sending_start_level_synced)
    );

//## Receiving Handshake Start

// Once in the receiving clock domain, we convert any toggle in level into
// a pulse, which signals new data is available.

    wire sending_handshake_start;

    Pulse_Generator
    new_sending_handshake
    (
        .clock              (receiving_clock),
        .level_in           (sending_start_level_synced),
        // verilator lint_off PINCONNECTEMPTY
        .pulse_posedge_out  (),
        .pulse_negedge_out  (),
        // verilator lint_on  PINCONNECTEMPTY
        .pulse_anyedge_out  (sending_handshake_start)
    );

// Since the receiving handshake may not complete immediately, we latch the
// pulse to hold it as `receiving_data_valid`.

    reg receiving_handshake_done = 1'b0;

    Pulse_Latch
    #(
        .RESET_VALUE    (1'b0)
    )
    pending_handshake
    (
        .clock          (receiving_clock),
        .clear          (receiving_handshake_done || receiving_clear),
        .pulse_in       (sending_handshake_start),
        .level_out      (receiving_data_valid)
    );

//## Receiving Handshake Finish

// The receiving handshake completes when `receiving_data_ready` goes (or
// already was) high, which we use to clear the latched
// `receiving_data_valid`. Conveniently, this also drops
// `receiving_handshake_done` in the next cycle, giving us a one-cycle pulse
// to signal the completion of the receiving handshake.

    always @(*) begin
        receiving_handshake_done = (receiving_data_valid == 1'b1) && (receiving_data_ready == 1'b1);
    end

// We then convert the completion of the receiving handshake into a level
// toggle back into the sending clock domain to complete the 2-phase
// handshake. This level does not toggle again until the end of the next
// receiving handshake, which since it can only happen after the next sending
// handshake completes, guarantees the level stays constant long enough to
// pass through the [CDC Synchronizer](./CDC_Bit_Synchronizer.html).

    wire receiving_handshake_level;

    Register_Toggle
    #(
        .WORD_WIDTH     (1),
        .RESET_VALUE    (1'b0)
    )
    finish_handshake
    (
        .clock          (receiving_clock),
        .clock_enable   (1'b1),
        .clear          (receiving_clear),
        .toggle         (receiving_handshake_done),
        .data_in        (receiving_handshake_level),
        .data_out       (receiving_handshake_level)
    );

// Then we synchronize the end of the 2-phase handshake into the sending clock
// domain.

    wire receiving_handshake_level_synced;

    CDC_Bit_Synchronizer
    #(
        .EXTRA_DEPTH        (EXTRA_DEPTH)  // Must be 0 or greater
    )
    into_sending
    (
        .receiving_clock    (sending_clock),
        .bit_in             (receiving_handshake_level),
        .bit_out            (receiving_handshake_level_synced)
    );

//## Sending Handshake Finish

// Finally, convert the synchronized receiving handshake completion into
// a pulse to both complete the sending handshake and start a new one if
// `sending_data_valid` remains high after the current cycle.

    Pulse_Generator
    finish_sending
    (
        .clock              (sending_clock),
        .level_in           (receiving_handshake_level_synced),
        // verilator lint_off PINCONNECTEMPTY
        .pulse_posedge_out  (),
        .pulse_negedge_out  (),
        // verilator lint_on  PINCONNECTEMPTY
        .pulse_anyedge_out  (sending_data_ready)
    );

endmodule

