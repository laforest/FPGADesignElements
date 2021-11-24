//# Pipeline Credit Buffer

// Pipelines the control and data of a ready/valid hanshake with zero or more
// plain [Registers](./Register.html) and
// a [FIFO](./Pipeline_FIFO_Buffer.html) to control the propagation delay and
// increase the possible clock frequency.  The latency from input to output is
// `PIPE_DEPTH` cycles, plus 2 from the output FIFO.

// In a nutshell, a credit buffer has an input interface which knows the
// latency of the register pipeline, tracks how many data transfers have been
// sent from the input interface to the output interface (which subtracts from
// the credit count), tracks how many transfers have left the output interface
// (which adds to the credit count), and thus how much capacity (credit)
// remains in the output interface buffer (minus any data in-flight in the
// pipeline). With that information, we can modulate when the input interface
// can accept new transfers. The FIFO at the output interface is necessary to
// receive any transfers still in-flight in the register pipelines while the
// input interface does not accept new transfers (credit is zero).

// Unlike a [Skid Buffer Pipeline](./Skid_Buffer_Pipeline.html), a Credit
// Buffer Pipeline can also improve concurrency by absorbing any
// irregularities in the transfer rates of the input and output interfaces: if
// one interface stalls, the other interface will not see that stall for as
// long as there is either enough available data or space in the FIFO.

// For longer pipelines, a Credit Buffer Pipeline uses less hardware than
// a Skid Buffer Pipeline, especially if the FIFO fits inside a denser Block
// RAM, and may fit some underlying devices better (e.g.: the routing
// hyper-registers in high-end Intel FPGAs). For reference, see Abbas and Betz
// ["Latency Insensitive Design Styles for FPGAs"](./reading.html#elastic)
// (FPL, 2018).

//## Configuration

// The `PIPE_DEPTH` parameter specifies the number of pipeline registers on
// the `input_ready` and `input_valid/input_data` paths. Adjust `PIPE_DEPTH`
// to break any critical paths between ready/valid interfaces. A value of zero
// will not implement any pipeline registers and reduces the design to a very
// short FIFO (see below for minimum size calculation).  

// The `FIFO_DEPTH` parameter specifies the depth of the FIFO buffer before
// the output port.  The minimum FIFO depth for correct operation and to
// support full throughput is the sum of:

// * `PIPE_DEPTH`: enough for the FIFO to completely receive the contents of
// the pipeline registers. 
// * `PIPE_DEPTH` again: to allow for the credits from completed output
// handshakes to reach the input interface before credits run out.
// * 2 cycles to account for the input/output FIFO latency.
// * 1 cycle to account for updating the credit counter.

// If the given `FIFO_DEPTH` parameter is smaller than this sum, it is
// automatically adjusted internally to this minimum sum. You can also specify
// a `FIFO_DEPTH` *larger* than this sum to allow the FIFO to absorb stalls on
// the input and output interfaces of duration less than or equal to the extra
// FIFO depth, which will improve concurrency.  Adjust the `FIFO_RAMSTYLE`
// parameter to match your desired FIFO implementation and your target device.

//## Reset

// The pipeline registers do not have enable or reset logic: they are plain,
// always-on registers, which minimises wiring and logic, and matches the
// Intel hyper-register implementation. Thus, **you must hold `clear` active
// for `PIPE_DEPTH`+1 cycles at a minimum to make sure all in-flight data and
// control signals have been flushed**, else you might release `clear` and
// start processing stale data/control still in the pipeline, or place the
// entire pipeline in an inconsistent state resulting in data loss at a much
// later time.

//## Ports and Parameters

`default_nettype none

module Pipeline_Credit_Buffer
#(
    parameter WORD_WIDTH    = 0,
    parameter PIPE_DEPTH    = 0,
    parameter FIFO_DEPTH    = 0,
    parameter FIFO_RAMSTYLE = ""
)
(
    input   wire                        clock,
    input   wire                        clear,

    input   wire                        input_valid,
    output  reg                         input_ready,
    input   wire    [WORD_WIDTH-1:0]    input_data,

    output  wire                        output_valid,
    input   wire                        output_ready,
    output  wire    [WORD_WIDTH-1:0]    output_data
);

    initial begin
        input_ready = 1'b1; // Empty at start, so accept data.
    end

// We need a minimum of 2x the pipeline latency in FIFO space to account for
// a full round-trip of the control signals, plus any other cycles of latency,
// so we don't stall prematurely or lose data.

    `include "max_function.vh"

    localparam COUNTER_LATENCY_CYCLES   = 1;
    localparam FIFO_LATENCY_CYCLES      = 2;
    localparam FIFO_DEPTH_MINIMUM       = (2 * PIPE_DEPTH) + FIFO_LATENCY_CYCLES + COUNTER_LATENCY_CYCLES;
    localparam FIFO_DEPTH_ADJUSTED      = max(FIFO_DEPTH, FIFO_DEPTH_MINIMUM); 

// As always, in a ready/valid handshake interface, data transfers and state
// changes can only happen when both ready and valid are asserted (the
// handshake completes). So we calculate those conditions for both interfaces
// here.

    reg input_handshake_done  = 1'b0;
    reg output_handshake_done = 1'b0;

    always @(*) begin
        input_handshake_done =  (input_valid  == 1'b1) && (input_ready  == 1'b1);
        output_handshake_done = (output_valid == 1'b1) && (output_ready == 1'b1);
    end

//## Input Interface

// The input interface is modulated by the credit counter: as long as we have
// send credits, we signal that we are ready to accept data.  Then we send off
// the data and valid pulses, and receive the ready pulses, both through
// simple register pipelines to reduce cycle time.

// The send credit counter starts by assuming everything is empty, so it has
// `FIFO_DEPTH_ADJUSTED` credits available to use.  We add one to the counter
// width to guarantee we can always contain the `FIFO_DEPTH_ADJUSTED` count
// plus the extra state of zero (no credits).

    `include "clog2_function.vh"

    localparam CREDIT_COUNTER_INITIAL   = FIFO_DEPTH_ADJUSTED;
    localparam CREDIT_COUNTER_WIDTH     = clog2(CREDIT_COUNTER_INITIAL) + 1;
    localparam CREDIT_COUNTER_ZERO      = {CREDIT_COUNTER_WIDTH{1'b0}};   
    localparam CREDIT_COUNTER_ONE       = {{CREDIT_COUNTER_WIDTH-1{1'b0}},1'b1};   

    reg                             credit_up_down = 1'b0; // 0/1 --> up/down
    reg                             credit_update  = 1'b0;
    wire [CREDIT_COUNTER_WIDTH-1:0] credit_available;

    Counter_Binary
    #(
        .WORD_WIDTH     (CREDIT_COUNTER_WIDTH),
        .INCREMENT      (CREDIT_COUNTER_ONE),
        .INITIAL_COUNT  (CREDIT_COUNTER_INITIAL [CREDIT_COUNTER_WIDTH-1:0])
    )
    send_credits
    (
        .clock          (clock),
        .clear          (clear),

        .up_down        (credit_up_down), // 0/1 --> up/down
        .run            (credit_update),

        .load           (1'b0),
        .load_count     (CREDIT_COUNTER_ZERO),

        .carry_in       (1'b0),
        // verilator lint_off PINCONNECTEMPTY
        .carry_out      (),
        .carries        (),
        .overflow       (),
        // verilator lint_on  PINCONNECTEMPTY

        .count          (credit_available)
    );

//## Pipelines

// The pipelines are simple registers with no control logic which are always
// enabled and cannot be cleared: if it was possible to control them from the
// input/output interfaces and meet timing, we wouldn't need a pipeline!

// First, we continuously pipeline the data from the input interface to the
// output interface.

    wire [WORD_WIDTH-1:0] input_data_pipelined;

    Register_Pipeline_Simple
    #(
        .WORD_WIDTH     (WORD_WIDTH),
        .PIPE_DEPTH     (PIPE_DEPTH)
    )
    input_data_pipe
    (
        // If PIPE_DEPTH is zero, these are unused
        // verilator lint_off UNUSED
        .clock          (clock),
        .clock_enable   (1'b1),
        .clear          (1'b0),
        // verilator lint_on  UNUSED
        .pipe_in        (input_data),
        .pipe_out       (input_data_pipelined)
    );

// Then, in parallel, we continuously pipeline a bit which indicates that the
// pipelined input data in the current cycle comes from a completed input
// handshake and is thus valid.

    wire input_handshake_done_pipelined;

    Register_Pipeline_Simple
    #(
        .WORD_WIDTH     (1),
        .PIPE_DEPTH     (PIPE_DEPTH)
    )
    input_handshake_pipe
    (
        // If PIPE_DEPTH is zero, these are unused
        // verilator lint_off UNUSED
        .clock          (clock),
        .clock_enable   (1'b1),
        .clear          (1'b0),
        // verilator lint_on  UNUSED
        .pipe_in        (input_handshake_done),
        .pipe_out       (input_handshake_done_pipelined)
    );

// Similarly and in parallel we continuously pipeline, from the output interface
// back to the input interface, a bit which indicates that an output handshake
// has completed in the current cycle and thus a space has been freed in the FIFO.

    wire output_handshake_done_pipelined;

    Register_Pipeline_Simple
    #(
        .WORD_WIDTH     (1'b1),
        .PIPE_DEPTH     (PIPE_DEPTH)
    )
    output_handshake_pipe
    (
        // If PIPE_DEPTH is zero, these are unused
        // verilator lint_off UNUSED
        .clock          (clock),
        .clock_enable   (1'b1),
        .clear          (1'b0),
        // verilator lint_on  UNUSED
        .pipe_in        (output_handshake_done),
        .pipe_out       (output_handshake_done_pipelined)
    );

// Finally, we store any valid pipelined input data into a FIFO until it can
// be read out. The FIFO itself is the output interface.

    Pipeline_FIFO_Buffer
    #(
        .WORD_WIDTH     (WORD_WIDTH),
        .DEPTH          (FIFO_DEPTH_ADJUSTED),
        .RAMSTYLE       (FIFO_RAMSTYLE)
    )
    output_storage
    (
        .clock          (clock),
        .clear          (clear),

        .input_valid    (input_handshake_done_pipelined),
        // verilator lint_off PINCONNECTEMPTY
        .input_ready    (),
        // verilator lint_on  PINCONNECTEMPTY
        .input_data     (input_data_pipelined),

        .output_valid   (output_valid),
        .output_ready   (output_ready),
        .output_data    (output_data)
    );

//## Control Logic

// The control logic for the `send_credits` counter is simple: at each cycle, if
// the input handshake completes, decrement the credit counter by one, if the
// output handshake completes, increment the credit counter by one, if both
// complete at the same time or no handshake completes this cycle, the counter
// stays constant.  So long as the send credit count is not zero, we can
// accept input data and send it through the pipeline.

    always @(*) begin
        credit_up_down  = (output_handshake_done_pipelined == 1'b0); // 0/1 --> up/down
        credit_update   = (output_handshake_done_pipelined != input_handshake_done);
        input_ready     = (credit_available != CREDIT_COUNTER_ZERO);
    end

endmodule

