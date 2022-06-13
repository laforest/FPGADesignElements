
//# Pipeline FIFO Buffer

// Decouples two sides of a ready/valid handshake to allow back-to-back
// transfers without a combinational path between input and output, thus
// pipelining the path to improve concurrency and/or timing. *Any FIFO depth
// is allowed, not only powers-of-2.* The input-to-output latency is 2 cycles.

// Since a FIFO buffer stores variable amounts of data, it will smooth out
// irregularities in the transfer rates of the input and output interfaces,
// and when used in pipeline loops, can store enough data to prevent
// artificial deadlocks (re: [Kahn Process
// Networks](https://en.wikipedia.org/wiki/Kahn_process_networks#Boundedness_of_channels)
// with bounded channels).

// **NOTE**: This module is not suitable for pipelining long combinational
// paths since it depends on a central buffer. If you need to pipeline a path
// to improve timing rather than concurrency, use a [Skid Buffer
// Pipeline](./Skid_Buffer_Pipeline.html) instead. You can also use
// a [Pipeline Credit Buffer](./Pipeline_Credit_Buffer.html) to improve both
// timing and concurrency, particularly for longer pipelines.

// *This module is a variation of the asynchronous [CDC FIFO
// Buffer](./CDC_FIFO_Buffer.html), directly derived from Clifford E.
// Cummings' <a
// href="http://www.sunburst-design.com/papers/CummingsSNUG2002SJ_FIFO1.pdf">Simulation
// and Synthesis Techniques for Asynchronous FIFO Design</a>, SNUG 2002, San
// Jose.*

//## Parameters, Ports, and Initializations

`default_nettype none

module Pipeline_FIFO_Buffer
#(
    parameter WORD_WIDTH                = 33,
    parameter DEPTH                     = 17,
    parameter RAMSTYLE                  = "block"
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
// construct the constants we work with.

    `include "clog2_function.vh"

    localparam WORD_ZERO    = {WORD_WIDTH{1'b0}};

    localparam ADDR_WIDTH   = clog2(DEPTH);
    localparam ADDR_ONE     = {{ADDR_WIDTH-1{1'b0}},1'b1};
    localparam ADDR_ZERO    = {ADDR_WIDTH{1'b0}};
    localparam ADDR_LAST    = DEPTH-1;

//## Data Path

// The buffer itself is a *synchronous* dual-port memory: one write port to
// insert data, and one read port to concurrently remove data, both clocked.
// Typically this memory will be a dedicated Block RAM, but can also be built
// from LUT RAM if the width and depth are small, or even plain registers for
// very small cases. Set the `RAMSTYLE` parameter as required.

// **NOTE**: There will *NEVER* be a concurrent read and write to the same
// address, so write-forwarding logic is not necessary. Guide your CAD tool as
// necessary to tell it there will never be read/write address collisions, so
// you can obtain the highest possible operating frequency. 

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
        .clock          (clock),
        .wren           (buffer_wren),
        .write_addr     (buffer_write_addr),
        .write_data     (input_data),

        .rden           (buffer_rden),
        .read_addr      (buffer_read_addr),
        .read_data      (output_data)
    );

//### Read/Write Address Counters

// The buffer read and write addresses are stored in counters which both start
// at (and `clear` to) `ADDR_ZERO`.  Each counter can only increment by
// `ADDR_ONE` at each read or write, and will wrap around to `ADDR_ZERO` if
// incremented past a value of `DEPTH-1`, labelled as `ADDR_LAST` (`load`
// overrides `run`). *The depth can be any positive number, not only
// a power-of-2*.

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

//### Wrap-Around Bits

// To distinguish between the empty buffer and full buffer cases, which both
// identically show as equal read and write buffer addresses, we keep track of
// each time an address wraps around to zero by toggling a bit.  *The
// addresses never pass eachother.* 

// If the write address runs ahead of the read address enough to wrap-around
// and reach the read address from behind, the buffer is full and all writes
// to the buffer halt until after a read happens. We detect this because the
// write address will have wrapped-around one more time than the read address,
// so their wrap-around bits will be different.

// Conversely, if the read address catches up to the write address from
// behind, the buffer is empty and all reads halt until after a write happens.
// In this case, the wrap-around bits are identical.

    reg  toggle_buffer_write_addr_wrap_around = 1'b0;
    wire buffer_write_addr_wrap_around;

    Register_Toggle
    #(
        .WORD_WIDTH     (1),
        .RESET_VALUE    (1'b0)
    )
    write_wrap_around_bit
    (
        .clock          (clock),
        .clock_enable   (1'b1),
        .clear          (clear),
        .toggle         (toggle_buffer_write_addr_wrap_around),
        .data_in        (buffer_write_addr_wrap_around),
        .data_out       (buffer_write_addr_wrap_around)
    );

    reg  toggle_buffer_read_addr_wrap_around = 1'b0;
    wire buffer_read_addr_wrap_around;

    Register_Toggle
    #(
        .WORD_WIDTH     (1),
        .RESET_VALUE    (1'b0)
    )
    read_wrap_around_bit
    (
        .clock          (clock),
        .clock_enable   (1'b1),
        .clear          (clear),
        .toggle         (toggle_buffer_read_addr_wrap_around),
        .data_in        (buffer_read_addr_wrap_around),
        .data_out       (buffer_read_addr_wrap_around)
    );

//## Control Path

//### Buffer States

// We describe the state of the buffer itself as the number of items currently
// stored in the buffer, as indicated by the read and write addresses and
// their wrap-around bits. We only care about the extremes: if the buffer
// holds no items, or if it holds its maximum number of items, as explained
// above.

    reg stored_items_zero = 1'b0;
    reg stored_items_max  = 1'b0;

    always @(*) begin
        stored_items_zero = (buffer_read_addr == buffer_write_addr) && (buffer_read_addr_wrap_around == buffer_write_addr_wrap_around);
        stored_items_max  = (buffer_read_addr == buffer_write_addr) && (buffer_read_addr_wrap_around != buffer_write_addr_wrap_around);
    end

//### Input Interface (Insert)

// The input interface is simple: if the buffer isn't at its maximum capacity,
// signal the input is ready, and when an input handshake completes, write the
// data directly into the buffer and increment the write address, wrapping
// around as necessary.

    reg insert = 1'b0;

    always @(*) begin
        input_ready                             = (stored_items_max == 1'b0);
        insert                                  = (input_valid      == 1'b1) && (input_ready  == 1'b1);

        buffer_wren                             = (insert == 1'b1);
        increment_buffer_write_addr             = (insert == 1'b1);
        load_buffer_write_addr                  = (increment_buffer_write_addr == 1'b1) && (buffer_write_addr == ADDR_LAST [ADDR_WIDTH-1:0]);
        toggle_buffer_write_addr_wrap_around    = (load_buffer_write_addr      == 1'b1);
    end

//### Output Interface (Remove)

// The output interface is not so simple because the output is registered, and
// so holds data independently of the buffer. We signal the output holds valid
// data whenever we can remove an item from the buffer and load it into the
// output register. We meet this condition if an output handshake completes,
// or if the buffer holds an item but the output register is not holding any
// valid data.  Also, we do not increment/wrap the read address if the
// previous item removed from the buffer and loaded into the output register
// was the last one.

    reg remove                  = 1'b0;
    reg output_leaving_idle     = 1'b0;
    reg load_output_register    = 1'b0;

    always @(*) begin
        remove                              = (output_valid == 1'b1) && (output_ready        == 1'b1);
        output_leaving_idle                 = (output_valid == 1'b0) && (stored_items_zero   == 1'b0);
        load_output_register                = (remove       == 1'b1) || (output_leaving_idle == 1'b1);

        buffer_rden                         = (load_output_register == 1'b1) && (stored_items_zero == 1'b0);
        increment_buffer_read_addr          = (load_output_register == 1'b1) && (stored_items_zero == 1'b0);
        load_buffer_read_addr               = (increment_buffer_read_addr == 1'b1) && (buffer_read_addr == ADDR_LAST [ADDR_WIDTH-1:0]);
        toggle_buffer_read_addr_wrap_around = (load_buffer_read_addr      == 1'b1);
    end

// Finally, `output_valid` must be registered to match the latency of the
// `buffer` output register.

    Register
    #(
        .WORD_WIDTH     (1),
        .RESET_VALUE    (1'b0)
    )
    output_data_valid
    (
        .clock          (clock),
        .clock_enable   (load_output_register == 1'b1),
        .clear          (clear),
        .data_in        (stored_items_zero == 1'b0),
        .data_out       (output_valid)
    );

endmodule

