
//# Pipeline FIFO Buffer

// Decouples two sides of a ready/valid handshake to allow back-to-back
// transfers without a combinational path between input and output, thus
// pipelining the path to improve concurrency and/or timing. The latency from
// input to output is 2 clock cycles. *Any FIFO depth is allowed, not only
// powers-of-2.* Raising `clear` will return the FIFO to the empty state.

// **NOTE**: This module is not suitable for pipelining long combinational
// paths since it depends on a central buffer. If you need to pipeline a path
// to improve timing rather than concurrency, use a [Skid Buffer
// Pipeline](./Skid_Buffer_Pipeline.html) instead.

// Since a FIFO buffer stores variable amounts of data, it will smooth out
// irregularities in the transfer rates of the input and output interfaces,
// and when used in pipeline loops, can store enough data to prevent
// artificial deadlocks (re: [Kahn Process
// Networks](https://en.wikipedia.org/wiki/Kahn_process_networks#Boundedness_of_channels)
// with bounded channels).

// *This module is a generalization of the [Skid
// Buffer](./Pipeline_Skid_Buffer.html), which acts as a 2-deep FIFO buffer.
// Go read it to get a deeper treatment of pipeline buffering requirements,
// and the particular idiom used to implement the control logic.*

`default_nettype none

module Pipeline_FIFO_Buffer
#(
    parameter WORD_WIDTH = 0,
    parameter DEPTH      = 0,
    parameter RAMSTYLE   = ""
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
        input_ready = 1'b1; // Empty at start, so accept data
    end

//## Constants

// From the FIFO `DEPTH`, we derive the bit width of the buffer addresses and
// item count, and construct the constants we work with.

    `include "clog2_function.vh"

    localparam WORD_ZERO    = {WORD_WIDTH{1'b0}};

    localparam ADDR_WIDTH   = clog2(DEPTH);
    localparam ADDR_ONE     = {{ADDR_WIDTH-1{1'b0}},1'b1};
    localparam ADDR_ZERO    = {ADDR_WIDTH{1'b0}};
    localparam ADDR_LAST    = DEPTH-1;

// Since the stored data count has to be able to represent `DEPTH` itself, and
// not a zero to `DEPTH-1` count of that quantity, we need an extra bit, to
// guarantee sufficient range.

    localparam COUNT_WIDTH  = ADDR_WIDTH + 1;
    localparam COUNT_ONE    = {{COUNT_WIDTH-1{1'b0}},1'b1};
    localparam COUNT_ZERO   = {COUNT_WIDTH{1'b0}};
    localparam COUNT_LAST   = DEPTH;
    localparam COUNT_UP     = 1'b0;
    localparam COUNT_DOWN   = 1'b1;

//## Data Path

// The buffer itself is a *synchronous* dual-port memory: one write port to
// insert data, and one read port to concurrently remove data. Typically this
// memory will be a dedicated Block RAM, but can also be built from LUT RAM if
// the width and depth are small, or even plain registers for very small
// cases. If your CAD tool does not support inference of memories as
// registers, you can instead chain together a few [Skid
// Buffers](./Pipeline_Skid_Buffer.html), though the latency will increase by
// 1 clock cycle per Skid Buffer.

// **NOTE**: There will *NEVER* be a concurrent read and write to the same
// address, so write-forwarding logic is not necessary, as specififed by the
// values of the `READ_NEW_DATA` and `RW_ADDR_COLLISION` parameters. Guide
// your CAD tool as necessary to tell it there will never be read/write
// address collisions, so you can obtain the highest possible operating
// frequency. 

// We initialize the read/write enables to zero, signifying an idle system.

    reg                     buffer_wren = 1'b0;
    wire [ADDR_WIDTH-1:0]   buffer_write_addr;

    reg                     buffer_rden = 1'b0;
    wire [ADDR_WIDTH-1:0]   buffer_read_addr;

    RAM_Simple_Dual_Port
    #(
        .WORD_WIDTH         (WORD_WIDTH),
        .ADDR_WIDTH         (ADDR_WIDTH),
        .DEPTH              (DEPTH),
        .RAMSTYLE           (RAMSTYLE),
        .READ_NEW_DATA      (0),
        .RW_ADDR_COLLISION  ("no"),
        .USE_INIT_FILE      (0),
        .INIT_FILE          (),
        .INIT_VALUE         (WORD_ZERO)
    )
    buffer
    (
        .clock              (clock),
        .wren               (buffer_wren),
        .write_addr         (buffer_write_addr),
        .write_data         (input_data),
        .rden               (buffer_rden),
        .read_addr          (buffer_read_addr),
        .read_data          (output_data)
    );

// Since the buffer is a synchronous RAM, it takes a clock cycle before the
// read data updates, so we pass along the read enable line (`buffer_rden`)
// through a register to synchronize it and signal valid read data
// (`output_valid`). However, the register needs separate control: for
// example, when the output interface reads out the last item out of the
// buffer, the output becomes invalid even though the buffer output is
// unchanged.

    reg update_output_valid = 1'b0;

    Register
    #(
        .WORD_WIDTH     (1),
        .RESET_VALUE    (1'b0)
    )
    output_data_valid
    (
        .clock          (clock),
        .clock_enable   (update_output_valid),
        .clear          (clear),
        .data_in        (buffer_rden),
        .data_out       (output_valid)
    );

//### Read/Write Address Counters

// The buffer read and write addresses are stored in counters, which both
// start at (and `clear` to) `ADDR_ZERO`. Each counter can only increment by
// `ADDR_ONE` at each read or write, and will wrap around to `ADDR_ZERO` if
// incremented past a value of `DEPTH-1`, labelled as `ADDR_LAST`. *The depth
// can be any positive number, not only a power-of-2.*

// **NOTE**: *The counters never pass eachother.* If the write counter runs
// ahead of the read counter enough to wrap-around and reach the read counter
// from behind, the buffer is full and all writes to the buffer halt until
// after a read happens.  Conversely, if the read counter catches up to the
// write counter from behind, the buffer is empty and all reads halt until
// after a write happens. In both the full and empty cases, both counters are
// equal but they get to that state by different paths, so we will need some
// extra state further down to make these two cases look different.

    reg increment_buffer_write_addr = 1'b0;
    reg load_buffer_write_addr      = 1'b0;

    Counter_Binary
    #(
        .WORD_WIDTH     (ADDR_WIDTH),
        .INCREMENT      (ADDR_ONE),
        .INITIAL_COUNT  (ADDR_ZERO)
    )
    write_address
    (
        .clock          (clock),
        .clear          (clear),
        .up_down        (1'b0), // 0/1 --> up/down
        .run            (increment_buffer_write_addr),
        .load           (load_buffer_write_addr),
        .load_count     (ADDR_ZERO),
        .carry_in       (1'b0),
        // verilator lint_off PINCONNECTEMPTY
        .carry_out      (),
        .carries        (),
        .overflow       (),
        // verilator lint_on  PINCONNECTEMPTY
        .count          (buffer_write_addr)
    );

    reg increment_buffer_read_addr = 1'b0;
    reg load_buffer_read_addr      = 1'b0;

    Counter_Binary
    #(
        .WORD_WIDTH     (ADDR_WIDTH),
        .INCREMENT      (ADDR_ONE),
        .INITIAL_COUNT  (ADDR_ZERO)
    )
    read_address
    (
        .clock          (clock),
        .clear          (clear),
        .up_down        (1'b0), // 0/1 --> up/down
        .run            (increment_buffer_read_addr),
        .load           (load_buffer_read_addr),
        .load_count     (ADDR_ZERO),
        .carry_in       (1'b0),
        // verilator lint_off PINCONNECTEMPTY
        .carry_out      (),
        .carries        (),
        .overflow       (),
        // verilator lint_on  PINCONNECTEMPTY
        .count          (buffer_read_addr)
    );

//### Stored Item Counter

// To distinguish between the empty and full cases, which both identically
// show as equal read and write counters, we also count the number of words
// currently stored in the FIFO. This is not the most compact way of
// expressing the difference between the empty and full cases, but it is the
// simplest and fastest, as we don't need to track the read and write
// addresses to see if they have wrapped around before they came to be equal
// to determine if the FIFO is full or empty.  All we need to do is count up
// or down by `COUNT_ONE`.

// Put another way, instead of having to compare the whole value of both
// address counters plus an extra empty/full bit, we only need to compare one
// counter to two constant values (for the empty and full cases) which is
// simpler and more local logic.

// Put yet another way, we found an equivalence between all possible pairs of
// read and write address values which represent the same amount of stored
// data, so we went from having to deal with (for a FIFO of depth N)
// ceil(2<sup>2log<sub>2</sub>(N)+1</sup>) possible states (two counters and
// an empty/full bit), to only ceil(2<sup>log<sub>2</sub>(N)</sup>) actual
// states (the number of stored words).

    reg                     update_buffer_data_count    = 1'b0;
    reg                     incr_decr_buffer_data_count = 1'b0;
    wire [COUNT_WIDTH-1:0]  buffer_data_count;

    Counter_Binary
    #(
        .WORD_WIDTH     (COUNT_WIDTH),
        .INCREMENT      (COUNT_ONE),
        .INITIAL_COUNT  (COUNT_ZERO)
    )
    data_count
    (
        .clock          (clock),
        .clear          (clear),
        .up_down        (incr_decr_buffer_data_count), // 0/1 --> up/down
        .run            (update_buffer_data_count),
        .load           (1'b0),
        .load_count     (COUNT_ZERO),
        .carry_in       (1'b0),
        // verilator lint_off PINCONNECTEMPTY
        .carry_out      (),
        .carries        (),
        .overflow       (),
        // verilator lint_on  PINCONNECTEMPTY
        .count          (buffer_data_count)
    );

//## Control Path

// For a depth of N, the FIFO buffer has N states:

// 1. Empty, representing 0 items in storage.
// 2. Busy, N-2 similar states, representing 1 to N-1 items in storage.
// 3. Full, representing N items in storage.

// The operations which transition between these states are:
 
// * the input interface **inserting** a data item into the datapath (`+`)
// * the output interface **removing** a data item from the datapath (`-`)
// * both interfaces inserting and removing at the same time (`+-`)

// We also descriptively name each transition between states. These names will
// show up later in the code as datapath transformations.

//<pre>
//                 /--\ +- flow              /--\ +- flow 
//                 |  |                      |  |
//          load   |  v    load       load   |  v    load
// -------   +    -------   +          +    -------   +     -------
//| Empty | ---> | Busy  | --->       ---> | Busy  | ----> | Full  |
//|   0   |      |   1   |      . . .      |  N-1  |       |   N   |
//|       | <--- |       | <---       <--- |       | <---  |       |
// -------    -   -------    -          -   -------    -    -------
//         unload         unload     unload         unload
//</pre>

// We can see from the resulting state diagram that when the datapath is
// empty, it can only support an insertion, and when it is full, it can only
// support a removal.  If the interfaces try to remove while Empty, or insert
// while Full, data will be duplicated or lost, respectively.

// We can also see that the state of the FIFO is exactly represented by the
// number of items currently stored in it, and that number can only stay put,
// increment by 1, or decrement by 1. Thus, the `data_count` counter will be
// our state variable, and we do not need to uniquely distinguish the state
// transitions.

    reg empty   = 1'b0;
    reg busy    = 1'b0;
    reg full    = 1'b0;

    always @(*) begin
        empty = (buffer_data_count == COUNT_ZERO);
        full  = (buffer_data_count == COUNT_LAST);
        busy  = (empty == 1'b0) && (full == 1'b0);
    end

//### Input Interface

// The input interface inserts directly into the buffer, and only signals the
// other end to stop if the buffer is full.

    reg insert = 1'b0;

    always @(*) begin
        input_ready = (full == 1'b0);
        insert      = (input_valid  == 1'b1) && (input_ready  == 1'b1);
    end

//### Output Interface

// The buffer output is registered, so the output interface is necessarily
// pipelined and works in parallel with the input interface. Keeping that
// pipeline full and signalling to the `read_address` and `data_count`
// counters when an item is removed from the buffer requires a separate little
// engine to continually read from the buffer when possible.

// Recall from above that `output_valid` is a registered version of
// `buffer_rden`, matching the latency of a buffer read and signalling when
// a buffer read has completed and new `output_data` is available.

// We update `output_valid` and try to read from the buffer if the other end
// of the output interface is ready (`output_ready` is high), or if
// `output_data` is currently invalid, so even if `output_ready` is low, we
// try and pre-load the output interface. A buffer read happens if the buffer
// is not empty. Otherwise, `output_valid` updates from a `buffer_rden` which
// is necessarily low, and thus `output_valid` goes (or remains) low in the
// next cycle. If we can read from the buffer, and `output_ready` is high,
// then we have removed an item from the buffer.

    reg remove = 1'b0;

    always @(*) begin
        update_output_valid = (output_valid == 1'b0) || (output_ready        == 1'b1);
        buffer_rden         = (empty        == 1'b0) && (update_output_valid == 1'b1);
        remove              = (buffer_rden  == 1'b1) && (output_ready        == 1'b1);
    end

//### Datapath Transformations

// Now that we have defined the possible states and operations of the
// datapath, we can define the datapath transformations, which are the edges
// between states. Or put otherwise: in which state(s) can the *insert* and/or
// *remove* operations happen, and what do they mean.

// After this point, we can describe the rest of the control logic using only
// transformations, without reference to states, I/O signals, or operations.

    reg load    = 1'b0; // Inserts data into buffer.
    reg unload  = 1'b0; // Remove data from buffer.
    reg flow    = 1'b0; // Inserts new data into buffer as stored data is removed.

    always @(*) begin
        load    = (full  == 1'b0) && (insert == 1'b1) && (remove == 1'b0);
        unload  = (empty == 1'b0) && (insert == 1'b0) && (remove == 1'b1);
        flow    = (busy  == 1'b1) && (insert == 1'b1) && (remove == 1'b1);
    end

//### Next-State Calculations

// Calculating the next state after each datapath transformation becomes the
// control lines of the `data_count` counter, where we increment, decrement,
// or leave constant the count of items in the buffer, which defines the state
// of the FIFO.

    always @(*) begin
        update_buffer_data_count    = (load == 1'b1) || (unload == 1'b1);
        incr_decr_buffer_data_count = (load == 1'b1) ? COUNT_UP : COUNT_DOWN;
    end

//### Control Signals

// Here, we increment the read/write addresses as necessary (they only ever
// increment), enable a write to the buffer as necessary, and wrap-around the
// read/write addresses when they reach the end of the buffer.

    always @(*) begin
        increment_buffer_write_addr = (load   == 1'b1) || (flow == 1'b1);
        increment_buffer_read_addr  = (unload == 1'b1) || (flow == 1'b1);
        buffer_wren                 = increment_buffer_write_addr;
        load_buffer_write_addr      = (increment_buffer_write_addr == 1'b1) && (buffer_write_addr == ADDR_LAST [ADDR_WIDTH-1:0]);
        load_buffer_read_addr       = (increment_buffer_read_addr  == 1'b1) && (buffer_read_addr  == ADDR_LAST [ADDR_WIDTH-1:0]);
    end

endmodule

