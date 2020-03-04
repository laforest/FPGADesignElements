
//# Pipeline Skid Buffer

// Decouples two sides of a ready/valid handshake to allow back-to-back
// transfers without a combinational path between input and output, thus
// pipelining the path.

// A skid buffer is the smallest FIFO, with only two entries.  It is useful
// when you need to pipeline the path between a sender and a receiver for
// concurrency and/or timing, but not to smooth-out data rate mismatches.  It
// also only requires two data registers, which at this scale is smaller than
// LUTRAMs or Block RAMs (depending on implementation), and has more freedom
// of placement and routing.

//## Background

// Networks-on-Chip (NoC) and elastic pipelines have as a fundamental building
// block a handshaking mechanism where each end of a link can signal if they
// have data to send ("valid"), or if they are able to receive data ("ready").
// When both ends agree (valid and ready both high), a data transfer occurs on
// that clock cycle.
 
// However, pipelining handshaking is more complicated: simply adding
// a pipeline register to the valid, ready, and data lines will work, but now
// each transfer take two cycles to start, and two cycles to stop.  This isn't
// bad in terms of bandwidth if you know you can transfer a block of data per
// handshake, but now the receiver has to be aware of how many pipeline stages
// exist between it and the sender, and thus must have sufficient internal
// buffering to absorb the data that keeps arriving after it signals it is no
// longer ready to receive more data.
 
// This is the basis of credit-based connections (which I'm not getting into
// here), which maximize bandwidth over long pipelines, but are overkill if you
// simply need to add a single pipeline stage between two ends, without having to
// modify them, so as to meet timing or allow each end to send off one item of
// data without having to wait for a response (thus overlapping communication and
// computation, which is desirable).

// This fundamental pipeline block is the *skid buffer*.

//## Figuring Out The Requirements

// To begin designing a skid buffer, let's imagine a single unit which can
// perform a valid/ready handshake and receive an input item of data, then
// performs the same handshake with the other end to output the data. 

//    Input                       Output
//    -----                       ------
//              -------------
//    ready <--|             |<-- ready
//    valid -->| Skid Buffer |--> valid
//    data  -->|             |--> data
//              -------------

// Ideally, the input and output interfaces operate concurrently for maximum
// bandwidth: in the same clock cycle, a new data item is received on the
// input interface and put into a register, and that same register is
// simultaneously read out by the output interface. However, if the output
// interface is not transfering data on a given cycle, the input interface
// must not transfer data during that cycle also, else we will overwrite the
// data register before it was read out. To avoid this problem, the input
// interface should declare itself not ready in the same cycle as the output
// interface declaring itself not ready. But this forms a direct combinational
// connection between them, not a pipelined one.  *If we could connect both
// interfaces directly, and not affect timing or concurrency, we wouldn't need
// pipelining in the first place!*
 
// To resolve this contradiction, we need an extra buffer register to capture
// the incoming data during a clock cycle where the input interface is
// transferring data, but the output interface isn't, and there is already
// data in the main register. Then, in the next cycle, the input interface can
// signal it is no longer ready, and no data gets lost. We can imagine this
// extra buffer register as allowing the input interface to "skid" to a stop,
// rather than stopping immediately, which we'd previously found contradicts
// our pipelining requirements.

`default_nettype none

module Pipeline_Skid_Buffer
#(
    parameter WORD_WIDTH = 0
)
(
    input   wire                        clock,
    input   wire                        clear,

    input   wire                        input_valid,
    output  wire                        input_ready,
    input   wire    [WORD_WIDTH-1:0]    input_data,

    output  wire                        output_valid,
    input   wire                        output_ready,
    output  wire    [WORD_WIDTH-1:0]    output_data
);

    localparam WORD_ZERO = {WORD_WIDTH{1'b0}};

//## Data Path

// Feed the data_out register either from the input_data, or a buffered copy of
// input_data. Write to registers only if enabled by control.

// Funneling into a single data_out register rather than selecting between two
// equal output registers avoids a mux after registers, fed by two data
// streams (thus more routing and delay). A single output register also
// retimes more easily into downstream logic.

// Set up the default control values to match the "empty" state of the skid
// buffer, so the first input_data to arrive ends up in the data_out by
// default.  We don't have to worry about state here, just pass the data
// through unless told otherwise.

    reg                     data_buffer_wren = 1'b0; // EMPTY at start, so don't load.
    wire [WORD_WIDTH-1:0]   data_buffer_out;

    Register
    #(
        .WORD_WIDTH     (WORD_WIDTH),
        .RESET_VALUE    (WORD_ZERO)
    )
    data_buffer_reg
    (
        .clock          (clock),
        .clock_enable   (data_buffer_wren),
        .clear          (clear),
        .data_in        (input_data),
        .data_out       (data_buffer_out)
    );

    reg                     data_out_wren       = 1'b1; // EMPTY at start, so accept data.
    reg                     use_buffered_data   = 1'b0;
    reg [WORD_WIDTH-1:0]    selected_data       = WORD_ZERO;

    always @(*) begin
        selected_data = (use_buffered_data == 1'b1) ? data_buffer_out : input_data;
    end

    Register
    #(
        .WORD_WIDTH     (WORD_WIDTH),
        .RESET_VALUE    (WORD_ZERO)
    )
    data_out_reg
    (
        .clock          (clock),
        .clock_enable   (data_out_wren),
        .clear          (clear),
        .data_in        (selected_data),
        .data_out       (output_data)
    );

//## Control Path

// We separate the control path so the associated data path does not have to
// know anything about the current state or its encoding.

// This FSM assumes the usual meaning and behaviour of valid/ready handshake
// signals: when both are high, data transfers at the end of the clock cycle.
// It is an error to raise ready when not able to accept data (thus losing the
// incoming data), or to raise valid when not able to send data (thus
// duplicating previously sent data). *These error situations are not
// handled.*

// To operate our datapath as a skid buffer, we need to understand which
// states we want to allow it to be in, and which state transitions we also
// allow. This skid buffer has three states:

// 1. It is Empty.
// 2. It is Busy, holding one item of data in the main register, either waiting
//    or actively transferring data through that register.
// 3. It is Full, holding data in both registers, and stopped until the main
//    register is emptied and simultaneously refilled from the buffer register, so no
//    data is lost or reordered.  (Without an available empty register, the
//    input interface cannot skid to a stop, so it must signal it is not ready.)
 
// The operations which transition between these states are:
 
// * the input interface inserting a data item into the datapath (`+`)
// * the output interface removing a data item from the datapath (`-`)
// * both interfaces inserting and removing at the same time (`+-`)

// We also descriptively name each transition between states. These names will
// show up later in the code.

//<pre>
//                 /--\ +- flow
//                 |  |
//          load   |  v   fill
// -------   +    ------   +    ------
//|       | ---> |      | ---> |      |
//| Empty |      | Busy |      | Full |
//|       | <--- |      | <--- |      |
// -------    -   ------    -   ------
//         unload         flush
//</pre>

// We can see from the resulting state diagram that when the datapath is
// empty, it can only support an insertion, and when it is full, it can only
// support a removal. *These constraints will become very important later on.*
// If the interfaces try to remove while Empty, or insert while Full, data
// will be duplicated or lost, respectively.

// This simple FSM description helped us clarify the problem, but it also
// glossed over the potential complexity of the implementation: 3 states, each
// connected to 2 signals (valid/ready) per interface, for a total of 16
// possible transitions out of each state, or 48 possible state transitions
// total.

// We don't want to have to manually enumerate all the transitions to then
// coalesce the equivalent ones and rule out all the impossible or illegal
// ones. Instead, if we express in logic the constraints on removals and
// insertions we determined from the state diagram, and the possible
// transformations on the datapath, we then get the state transition logic and
// datapath control signal logic almost for free.

// Lets describe the possible states of the datapath, and initialize it.  This
// code describes a binary state encoding, but the CAD tool can re-encode and
// re-number the state encoding. Usually this is beneficial, but if the
// states+inputs fit in a single LUT, forcing binary encoding reduces area.
// See what works best (i.e.: reaches the highest speed) for your given FPGA.

    localparam STATE_BITS = 2;

    localparam [STATE_BITS-1:0] EMPTY = 'd0; // Output and buffer registers empty
    localparam [STATE_BITS-1:0] BUSY  = 'd1; // Output register holds data
    localparam [STATE_BITS-1:0] FULL  = 'd2; // Both output and buffer registers hold data
    // There is no case where only the buffer register would hold data.

    // No handling of erroneous and unreachable state 3.
    // We could check and raise an error flag.

    wire [STATE_BITS-1:0] state;
    reg  [STATE_BITS-1:0] state_next = EMPTY;

// Now, let's express the constraints we figured out from the state diagram:
 
// * The input interface can only insert when the datapath is not full.
// * The output interface can only remove data when the datapath is not empty.
 
// We do this by computing the allowable output read/valid handshake signals
// based on the datapath state. We use `state_next` so we can have nice
// registered outputs. This little bit of code prunes away a large number of
// invalid state transitions. If some other logic seems to be missing, first
// see if this code has made it unnecessary.

// *This tiny bit of code is critical* since it also implies the fundamental
// operating assumptions of a skid buffer: that one interface cannot have its
// current state depend on the current state of the other interface, as that
// would be a combinational path between both interfaces.

// Compute `ready` for the input interface

    Register
    #(
        .WORD_WIDTH     (1),
        .RESET_VALUE    (1'b1) // EMPTY at start, so accept data
    )
    input_ready_reg
    (
        .clock          (clock),
        .clock_enable   (1'b1),
        .clear          (clear),
        .data_in        (state_next != FULL),
        .data_out       (input_ready)
    );

// Compute `valid` for the output interface

    Register
    #(
        .WORD_WIDTH     (1),
        .RESET_VALUE    (1'b0)
    )
    output_valid_reg
    (
        .clock          (clock),
        .clock_enable   (1'b1),
        .clear          (clear),
        .data_in        (state_next != EMPTY),
        .data_out       (output_valid)
    );

// After, let's describe the interface signal conditions which implement our
// two basic operations on the datapath: insert and remove. This also weeds
// out a number of possible state transitions.

    reg insert = 1'b0;
    reg remove = 1'b0;

    always @(*) begin
        insert = (input_valid  == 1'b1) && (input_ready  == 1'b1);
        remove = (output_valid == 1'b1) && (output_ready == 1'b1);
    end

// Now that we have our datapath states and operations, let's use them to
// describe the possible transformations to the datapath, and in which state
// they can happen.  You'll see that these exactly describe each of the
// 5 edges in the state diagram, and since we've pruned the space of possible
// interface conditions, we only need the minimum logic to describe them, and
// this logic gets re-used a lot later on, simplifying the code.


    reg load    = 1'b0; // Empty datapath inserts data into output register.
    reg flow    = 1'b0; // New inserted data into output register as the old data is removed.
    reg fill    = 1'b0; // New inserted data into buffer register. Data not removed from output register.
    reg flush   = 1'b0; // Move data from buffer register into output register. Remove old data. No new data inserted.
    reg unload  = 1'b0; // Remove data from output register, leaving the datapath empty.

    always @(*) begin
        load    = (state == EMPTY) && (insert == 1'b1) && (remove == 1'b0);
        flow    = (state == BUSY)  && (insert == 1'b1) && (remove == 1'b1);
        fill    = (state == BUSY)  && (insert == 1'b1) && (remove == 1'b0);
        flush   = (state == FULL)  && (insert == 1'b0) && (remove == 1'b1);
        unload  = (state == BUSY)  && (insert == 1'b0) && (remove == 1'b1);
    end

// And now we simply need to calculate the next state after each datapath
// transformations:

    always @(*) begin
        state_next = (load   == 1'b1) ? BUSY  : state;
        state_next = (flow   == 1'b1) ? BUSY  : state_next;
        state_next = (fill   == 1'b1) ? FULL  : state_next;
        state_next = (flush  == 1'b1) ? BUSY  : state_next;
        state_next = (unload == 1'b1) ? EMPTY : state_next;
    end

    Register
    #(
        .WORD_WIDTH     (STATE_BITS),
        .RESET_VALUE    (EMPTY)         // Initial state
    )
    state_reg
    (
        .clock          (clock),
        .clock_enable   (1'b1),
        .clear          (clear),
        .data_in        (state_next),
        .data_out       (state)
    );

// Similarly, from the datapath transformations, we can compute the necessary
// control signals to the datapath. These are not registered here, as they end
// at registers in the datapath.

    always @(*) begin
        data_out_wren     = (load  == 1'b1) || (flow == 1'b1) || (flush == 1'b1);
        data_buffer_wren  = (fill  == 1'b1);
        use_buffered_data = (flush == 1'b1);
    end

endmodule

// For a 64-bit connection, the resulting skid buffer uses 128 registers for
// the buffers, 4 to 9 registers (and associated LUTs) for the FSM and
// interface outputs, depending on the particular state encoding chosen by the
// CAD tool, and easily reaches a high operating speed.

