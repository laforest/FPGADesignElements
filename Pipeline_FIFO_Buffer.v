
//# Pipeline FIFO Buffer

// Decouples two sides of a ready/valid handshake to allow back-to-back
// transfers without a combinational path between input and output, thus
// pipelining the path to improve concurrency and/or timing.

// *This module is a generalization of the [Skid
// Buffer](./Pipeline_Skid_Buffer.html). Go read it to get a deeper treatment
// of pipeline buffering theory, and the particular method used to implement
// the control logic.*

// Since a FIFO buffer stores larger and variable amounts of data, it will
// smooth out irregularities in the transfer rates of the input and output
// ports, and when used in pipeline loops, can store enough data to prevent
// deadlocks (re: [Kahn Process
// Networks](https://en.wikipedia.org/wiki/Kahn_process_networks#Boundedness_of_channels)
// with bounded channels).

`default_nettype none

module Pipeline_FIFO_Buffer
#(
    parameter WORD_WIDTH = 32,
    parameter DEPTH      = 512,
    parameter RAMSTYLE   = "M10K"
)
(
    input   wire                        clock,
    input   wire                        clear,

    input   wire                        input_valid,
    output  reg                         input_ready,
    input   wire    [WORD_WIDTH-1:0]    input_data,

    output  reg                         output_valid,
    input   wire                        output_ready,
    output  wire    [WORD_WIDTH-1:0]    output_data
);

    initial begin
        input_ready     = 1'b1; // Empty at start, so accept data
        output_valid    = 1'b0;
    end

    `include "clog2_function.vh"

    localparam                  WORD_ZERO   = {WORD_WIDTH{1'b0}};

    localparam                  ADDR_WIDTH  = clog2(DEPTH);
    localparam                  ADDR_ONE    = {{ADDR_WIDTH-1{1'b0}},1'b1};
    localparam                  ADDR_ZERO   = {ADDR_WIDTH{1'b0}};
    localparam [ADDR_WIDTH-1:0] ADDR_LAST   = DEPTH [ADDR_WIDTH-1:0] - ADDR_ONE;

    // Since the stored data count has to be able to represent DEPTH itself,
    // and not a zero-based count of that quantity.
    localparam                   COUNT_WIDTH = ADDR_WIDTH + 1;
    localparam                   COUNT_ONE   = {{COUNT_WIDTH-1{1'b0}},1'b1};
    localparam                   COUNT_ZERO  = {COUNT_WIDTH{1'b0}};
    localparam [COUNT_WIDTH-1:0] COUNT_LAST  = DEPTH;
    localparam                   COUNT_UP    = 1'b0;
    localparam                   COUNT_DOWN  = 1'b1;

//## Data Path

// The data path is a simple dual-port memory: one write port to receive data,
// and one read port to concurrently send data. Typically this memory will be
// a dedicated Block RAM, but can also be LUT RAM if the width and depth are
// small, or even plain registers for very small cases. (Though at that latter
// point, you might be better off chaining a couple of [Skid
// Buffers](./Pipeline_Skid_Buffer.html) instead.)

// NOTE: there will NEVER be a concurrent read and write to the same address,
// so write-forwarding logic is not necessary. Guide your CAD tool as
// necessary to tell it this fact, so you can obtain the highest possible
// operating frequency.

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

// The buffer read and write addresses are stored in counters, which both
// start at (and `clear` to) `ADDR_ZERO`. Each counter can only increment by
// one at each read or write, and will wrap around to zero if incremented past
// a value of `DEPTH-1`, labelled as `ADDR_LAST`. *The depth can be any
// arbitrary number, not only a power-of-2.*

// *The counters never pass eachother.* If the write counter runs ahead of the
// read counter enough to wrap-around and reach the read counter from behind,
// the buffer is full and all writes to the buffer halt until after a read
// happens.  Conversely, if the read counter catches up to the write counter
// from behind, the buffer is empty and all reads halt until after a write
// happens. In both the full and empty cases, both counters are equal but they
// get to that state by different paths, so we will need some extra state
// further down to make these two cases look different.

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
        // verilator lint_on  PINCONNECTEMPTY
        .count          (buffer_read_addr)
    );

// To distinguish between the empty and full cases, which both identically
// show as equal read and write counters, we also count the number of words
// currently stored in the FIFO. This is not the most compact way of
// expressing the difference between the empty and full cases, but it is the
// simplest and fastest, as we don't need to track the read and write
// addresses to see if they have wrapped around before they came to be equal
// to determine if the FIFO is full or empty.  All we need to do is count up
// or down by 1.

// Put another way, we found an equivalence between all possible pairs of read
// and write address values which represent the same amount of stored data, so
// we went from having to deal with (for a FIFO of depth N)
// ceil(2<sup>2log<sub>2</sub>(N)+1</sup>) possible states (two counters and
// an empty/full bit), to only ceil(2<sup>log<sub>2</sub>(N)</sup>) actual
// states (the number of stored words).

// A FIFO has a rather larger number of states. For example, a 512 entry FIFO
// has 9 bits for the read address, and either 9 bits for a write address, or
// 9 bits for a stored data count, and a single bit to distinguish between the
// otherwise idential full and empty states, where the read and write
// addresses are equal. In either case, the missing write address or data
// count can be calculated with a single addition or subtraction.  Other pairs
// of these three 9-bit values are also possible, plus the empty/full bit.
// With a total of 19 bits of state, the 512-entry FIFO has
// <code>2<sup>19</sup> = 524,288</code> states!

// However, a lot of these states are "similar": there is the same 512
// transitions from any of the 512 empty states (where the read and write
// addresses match and no data is stored), to the corresponding full state
// (equal read and write addresses, after a wraparound, but all storage
// locations holding data). A read during this state progression simply moves
// to a parallel "track" of states, with the same set of 512 transitions.
// This suggests it might be possible to only need 512 states to describe the
// operation of the FIFO.

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
        // verilator lint_on  PINCONNECTEMPTY
        .count          (buffer_data_count)
    );

//## Control Path

// For a depth of N, the FIFO buffer has N states:

// 1. Empty, representing 0 items in storage.
// 2. Busy, N-2 identical versions, representing 1 to N-1 items in storage.
// 3. Full, representing N items in storage.

// The operations which transition between these states are:
 
// * the input interface inserting a data item into the datapath (`+`)
// * the output interface removing a data item from the datapath (`-`)
// * both interfaces inserting and removing at the same time (`+-`)

// We also descriptively name each transition between states. These names will
// show up later in the code.

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
// support a removal. *These constraints will become very important later on.*
// If the interfaces try to remove while Empty, or insert while Full, data
// will be duplicated or lost, respectively.

// We can also see that the state of the FIFO is exactly represented by the
// number of items currently stored in it, and that number can only stay put,
// increment by 1, or decrement by 1. Thus, the `data_count` counter will be
// our state variable.

    reg empty   = 1'b0;
    reg busy    = 1'b0;
    reg full    = 1'b0;

    always @(*) begin
        empty = (buffer_data_count == COUNT_ZERO);
        full  = (buffer_data_count == COUNT_LAST);
        busy  = (empty == 1'b0) && (full == 1'b0);
    end

// Now, let's express the constraints we figured out from the state diagram:
 
// * The input interface can only insert when the datapath is not full.
// * The output interface can only remove data when the datapath is not empty.
 
// We do this by computing the allowable output read/valid handshake signals
// based on the datapath state. This little bit of code prunes away a large
// number of invalid state transitions. If some other logic seems to be
// missing, first see if this code has made it unnecessary.

// *This tiny bit of code is critical* since it also implies the fundamental
// operating assumptions of a FIFO buffer: that one interface cannot have its
// current state depend on the current state of the other interface, as that
// would be a combinational path between both interfaces.

    always @(*) begin
        input_ready  = (full  == 1'b0);
        output_valid = (empty == 1'b0);
    end

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

    reg load    = 1'b0; // Inserts data into buffer.
    reg flow    = 1'b0; // Inserts new data into buffer as stored data is removed.
    reg unload  = 1'b0; // Remove data from buffer.

    always @(*) begin
        load    = (full  == 1'b0) && (insert == 1'b1) && (remove == 1'b0);
        unload  = (empty == 1'b0) && (insert == 1'b0) && (remove == 1'b1);
        flow    = (busy  == 1'b1) && (insert == 1'b1) && (remove == 1'b1);
    end

// And now we simply need to calculate the next state after each datapath
// transformations. Here, this becomes the `data_count` counter control.

    always @(*) begin
        update_buffer_data_count    = (load == 1'b1) || (unload == 1'b1);
        incr_decr_buffer_data_count = (load == 1'b1) ? COUNT_UP : COUNT_DOWN;
    end

// Similarly, from the datapath transformations, we can compute the necessary
// control signals to the datapath. These are not registered here, as they end
// at registers in the datapath.

    always @(*) begin
        increment_buffer_write_addr = (load   == 1'b1) || (flow == 1'b1);
        increment_buffer_read_addr  = (unload == 1'b1) || (flow == 1'b1);
        buffer_wren                 = increment_buffer_write_addr;
        buffer_rden                 = increment_buffer_read_addr;
        load_buffer_write_addr      = (increment_buffer_write_addr == 1'b1) && (buffer_write_addr == ADDR_LAST);
        load_buffer_read_addr       = (increment_buffer_read_addr  == 1'b1) && (buffer_read_addr  == ADDR_LAST);
    end

endmodule

