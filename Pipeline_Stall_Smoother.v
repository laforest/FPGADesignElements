
//# Pipeline Stall Smoother

// Prevents pipeline stalls at the output interface, given a known maximum
// input pipeline stall duration, by buffering a sufficient number of items
// from the input pipeline before allowing the output pipeline to start
// providing data.

// This controlled buffering allows any periodic stalls at the input (e.g. CDC
// latency) to resolve before the output runs out of data, thus ensuring an
// uninterrupted flow of data at the output once started.  Once started, the
// output provides data continuously until it stalls from lack of input data,
// then the buffering starts again.

// Alternately, if the input data meets an externally calculated trigger
// condition (e.g.: the end of a packet), the output will begin providing data
// only after sufficient time has passed (assuming 1 cycle/transfer), even if
// not enough items have arrived, to ensure that any pending input stall has
// time to complete and thus not stall the continuous output.

// *This whole mechanism depends on the average input and output data rates
// being identical, otherwise propagating stalls between input and output is
// inevitable.* You can externally detect an input stall propagated to the
// output by using a [Pulse Generator](./Pulse_Generator.html) to detect
// a negative edge on the `output_valid` port.

//## Parameters

// Set `WORD_WIDTH` to the width in bits of each transfer. Set `RAMSTYLE` to
// control the implementation of the FIFO buffer storage (see your CAD tool
// and target device for available option). Set `GATE_DATA` to a non-zero
// value to zero-out `output_data` when waiting to start output transfers.
// Select `GATE_IMPLEMENTATION` to best match your CAD tools and FPGA device,
// but it can virtually always be left as "AND".

// Note that if you want to precisely control the FIFO storage size (e.g.: to
// use up exactly one Block RAM), you must make `MAX_STALL_CYCLES` equal to
// the depth of your desired storage *minus one*. Values below 2 will be
// adjusted back up to 2, using up a total of 3 FIFO storage locations.

//## Ports and Constants

`default_nettype none

module Pipeline_Stall_Smoother
#(
    parameter       WORD_WIDTH          = 32,
    parameter       RAMSTYLE            = "block",
    parameter       MAX_STALL_CYCLES    = 7,
    parameter       GATE_DATA           = 0,
    parameter       GATE_IMPLEMENTATION = "AND"
)
(
    input   wire                        clock,
    input   wire                        clear,

    input   wire                        input_valid,
    output  wire                        input_ready,
    input   wire    [WORD_WIDTH-1:0]    input_data,

    input   wire                        input_trigger, // Preferably a one-cycle pulse high

    output  wire                        output_valid,
    input   wire                        output_ready,
    output  wire    [WORD_WIDTH-1:0]    output_data
);

// The `Pipeline_FIFO_Buffer` has a latency from input to output of 2 cycles,
// so we cannot specify a shorter input stall duration: single-cycle stalls are
// treated as two-cycle stalls.

// Also, to prevent creating a 1-cycle stall at the input when the FIFO buffer
// fills sufficiently to absorb the specified maximum input stall duration, we
// must add 1 to the specified `MAX_STALL_CYCLES` so that we have 1 storage
// location left to take in input during the cycle the first buffered output
// is sent out.

    `include "clog2_function.vh"
    `include "max_function.vh"

    localparam FIFO_DEPTH = max(MAX_STALL_CYCLES, 2) + 1;

//## Stored Item Counting

// Since the stored data count has to be able to represent `FIFO_DEPTH` itself, and
// not a zero to `FIFO_DEPTH-1` count of that quantity, we need an extra bit to
// guarantee sufficient range.

    localparam BUFFER_COUNT_WIDTH  = clog2(FIFO_DEPTH) + 1;
    localparam BUFFER_COUNT_ONE    = {{BUFFER_COUNT_WIDTH-1{1'b0}},1'b1};
    localparam BUFFER_COUNT_ZERO   = {BUFFER_COUNT_WIDTH{1'b0}};
    localparam BUFFER_COUNT_LAST   = FIFO_DEPTH [BUFFER_COUNT_WIDTH-1:0];
    localparam BUFFER_COUNT_UP     = 1'b0;
    localparam BUFFER_COUNT_DOWN   = 1'b1;

    reg                             buffer_count_up_down   = BUFFER_COUNT_UP;
    reg                             buffer_count_run       = 1'b0;
    wire [BUFFER_COUNT_WIDTH-1:0]   items_in_buffer;

    Counter_Binary
    #(
        .WORD_WIDTH     (BUFFER_COUNT_WIDTH),
        .INCREMENT      (BUFFER_COUNT_ONE),
        .INITIAL_COUNT  (BUFFER_COUNT_ZERO)
    )
    buffer_occupancy
    (
        .clock          (clock),
        .clear          (clear),

        .up_down        (buffer_count_up_down), // 0/1 --> up/down
        .run            (buffer_count_run),

        .load           (1'b0),
        .load_count     (BUFFER_COUNT_ZERO),

        .carry_in       (1'b0),
        //verilator lint_off PINCONNECTEMPTY
        .carry_out      (),
        .carries        (),
        .overflow       (),
        //verilator lint_on  PINCONNECTEMPTY

        .count          (items_in_buffer)
    );

//## Trigger Delay 

// Since the delay count has to be able to represent `FIFO_DEPTH` itself, and
// not a zero to `FIFO_DEPTH-1` count of that quantity, we need an extra bit to
// guarantee sufficient range.

    localparam TRIGGER_COUNT_WIDTH  = clog2(FIFO_DEPTH) + 1;
    localparam TRIGGER_COUNT_ONE    = {{TRIGGER_COUNT_WIDTH-1{1'b0}},1'b1};
    localparam TRIGGER_COUNT_ZERO   = {TRIGGER_COUNT_WIDTH{1'b0}};
    localparam TRIGGER_COUNT_LAST   = FIFO_DEPTH [TRIGGER_COUNT_WIDTH-1:0];
    localparam TRIGGER_COUNT_UP     = 1'b0;

    reg                             trigger_count_reload    = 1'b0;
    reg                             trigger_count_run       = 1'b0;
    wire [TRIGGER_COUNT_WIDTH-1:0]  cycles_since_trigger;

    Counter_Binary
    #(
        .WORD_WIDTH     (TRIGGER_COUNT_WIDTH),
        .INCREMENT      (TRIGGER_COUNT_ONE),
        .INITIAL_COUNT  (TRIGGER_COUNT_ZERO)
    )
    trigger_delay
    (
        .clock          (clock),
        .clear          (clear),

        .up_down        (TRIGGER_COUNT_UP), // 0/1 --> up/down
        .run            (trigger_count_run),

        .load           (trigger_count_reload),
        .load_count     (TRIGGER_COUNT_ZERO),

        .carry_in       (1'b0),
        //verilator lint_off PINCONNECTEMPTY
        .carry_out      (),
        .carries        (),
        .overflow       (),
        //verilator lint_on  PINCONNECTEMPTY

        .count          (cycles_since_trigger)
    );

//## Stored Item Buffering

    wire                    output_valid_internal;
    wire                    output_ready_internal;
    wire [WORD_WIDTH-1:0]   output_data_internal;

    Pipeline_FIFO_Buffer
    #(
        .WORD_WIDTH     (WORD_WIDTH),
        .DEPTH          (FIFO_DEPTH),
        .RAMSTYLE       (RAMSTYLE)
    )
    smoothing_buffer
    (
        .clock          (clock),
        .clear          (clear),

        .input_valid    (input_valid),
        .input_ready    (input_ready),
        .input_data     (input_data),

        .output_valid   (output_valid_internal),
        .output_ready   (output_ready_internal),
        .output_data    (output_data_internal)
    );

//## Control Logic

// Buffer the input data in the `smoothing_buffer` until there is enough to
// absorb `MAX_STALL_CYCLES` cycles of input stall, then allow that buffered
// data to exit the output. If we run out of buffered data (which should never
// happen during steady flow state with a known maximum input stall duration),
// then revert back to buffering data.

    localparam STATE_BUFFERING = 1'b0;
    localparam STATE_SENDING   = 1'b1; 

    wire state;
    reg  state_next = STATE_BUFFERING;

    Register
    #(
        .WORD_WIDTH     (1),
        .RESET_VALUE    (STATE_BUFFERING)
    )
    state_storage
    (
        .clock          (clock),
        .clock_enable   (1'b1),
        .clear          (clear),
        .data_in        (state_next),
        .data_out       (state)
    );

// Common logic for control. Everything must follow the state of the
// interfaces, else data can get lost.

    reg input_handshake_done    = 1'b0;
    reg output_handshake_done   = 1'b0;

    always @(*) begin
        input_handshake_done    = (input_valid  == 1'b1) && (input_ready  == 1'b1);
        output_handshake_done   = (output_valid == 1'b1) && (output_ready == 1'b1);
    end

// Control the buffer counter. Increment when data enters, decrement when data
// leaves, and stay constant otherwise.

    always @(*) begin
        buffer_count_run        = (input_handshake_done != output_handshake_done);
        buffer_count_up_down    = (input_handshake_done == 1'b0) && (output_handshake_done == 1'b1) ? BUFFER_COUNT_DOWN : BUFFER_COUNT_UP;
        buffer_count_up_down    = (input_handshake_done == 1'b1) && (output_handshake_done == 1'b0) ? BUFFER_COUNT_UP   : buffer_count_up_down;
    end

// Control the trigger counter. Start counting when a trigger is seen. Reset
// when sending begins, which is when this counter completes, at least.

    reg  trigger_clear = 1'b0;
    wire trigger_latched;

    Pulse_Latch
    #(
        .RESET_VALUE    (1'b0)
    )
    capture_trigger
    (
        .clock          (clock),
        .clear          (trigger_clear),
        .pulse_in       (input_trigger),
        .level_out      (trigger_latched)
    );

    always @(*) begin
        trigger_count_run       = (trigger_latched      == 1'b1);
        trigger_count_reload    = (cycles_since_trigger == TRIGGER_COUNT_LAST);
        trigger_clear           = (trigger_count_reload == 1'b1);
    end

// Calculate the next state. Buffer until full or until trigger. Then send
// until empty, then buffer again.

    always @(*) begin
        state_next              = (items_in_buffer == BUFFER_COUNT_LAST) || (cycles_since_trigger == TRIGGER_COUNT_LAST) ? STATE_SENDING   : state;
        state_next              = (items_in_buffer == BUFFER_COUNT_ZERO)                                                 ? STATE_BUFFERING : state_next;
    end

// If we are not sending data, gate the output handshake, and optionally gate
// the data also.

    Pipeline_Gate
    #(
        .WORD_WIDTH     (WORD_WIDTH),
        .IMPLEMENTATION (GATE_IMPLEMENTATION),
        .GATE_DATA      (GATE_DATA)
    )
    output_gate
    (
        .enable         (state == STATE_SENDING),

        .input_ready    (output_ready_internal),
        .input_valid    (output_valid_internal),
        .input_data     (output_data_internal),

        .output_valid   (output_valid),
        .output_ready   (output_ready),
        .output_data    (output_data)
    );

endmodule

