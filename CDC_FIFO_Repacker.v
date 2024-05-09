
//# CDC (Clock Domain Crossing) FIFO Repacker

// Takes in a ready/valid handshake of a given word width, buffers it into
// a FIFO and passes it into another clock domain with full throughput, and
// outputs a ready/valid handshake with a *different* word width. The data is
// repacked without gaps into the new word width. The words widths are
// arbitrary and need not be multiples of eachother.

// The minimum input-to-output latency is 7 cycles when both
// clocks are plesiochronous.

//## Asynchronous Clocks

// This FIFO Repacker supports having the input and output interfaces each on
// their own mutually asynchronous clock (without knowledge or restriction on
// their relative clock frequencies or phase).  Using a FIFO for data tranfer
// between asynchronous clock domains allows multiple transfers to overlap
// with the CDC synchronization overhead. Once the CDC synchronization is done,
// all the previously written data in one clock domain can be freely read out
// in the other clock domain without further overhead.

//## Trading Off Size for Simplicity

// Usually, a repacker is implemented with a minimally sized ring buffer with
// a pre-calculated read/write schedule which covers the whole sequence of
// possible amounts of data in the buffer at a given time. This is a complex
// schedule which resembles pseudo-random number generation and is likely
// unique for every pair of input/output widths. This also means the read side
// must be able to read into every possible offset into the ring buffer as
// given by the schedule, which can create wide multiplexers. The minimum size
// of the buffer is also a function of the computed schedule.

// Instead, let's trade-off using more storage to obtain the implicit simplest
// schedule: we use the Least Common Multiple of the input and output widths,
// which is the smallest buffer which holds an integer number of input and
// output entries at the same time. Then the behaviour of the buffer reduces
// to that of a FIFO buffer, albeit with different input and output word
// widths. This approach tends to minimize the amount of multiplexing and does
// not require computing any schedules (only plain counting). We only need to
// specify the input and output widths and everything is computed for us.

// **NOTE**: Using the LCM depth does not guarantee full throughput. A multiple
// of the LCM may be needed. See below.

//## Resets

// Since the input and output interfaces are asynchronous to eachother, they
// each have their own locally-synchronous `clear` reset signal. However, it
// makes no sense to reset one interface only, as that would corrupt the
// read/write addresses and duplicate or lose data. *Both interfaces must be reset
// together.* Pick one interface reset as the primary reset, then synchronize
// it into the clock domain of the other interface using a [Reset
// Synchronizer](./Reset_Synchronizer.html).

// **NOTE**: Both interfaces must be out of reset before beginning operation,
// otherwise a CDC synchronization from one domain into another domain which
// is still under reset will be lost, and the system state becomes
// inconsistent.

//## Parameters, Ports, and Constants

`default_nettype none

module CDC_FIFO_Repacker
#(
    parameter WORD_WIDTH_INPUT  = 0,
    parameter WORD_WIDTH_OUTPUT = 0,
    parameter CDC_EXTRA_STAGES  = 0
)
(
    input   wire                            input_clock,
    input   wire                            input_clear,
    input   wire                            input_valid,
    output  reg                             input_ready,
    input   wire    [WORD_WIDTH_INPUT-1:0]  input_data,

    input   wire                            output_clock,
    input   wire                            output_clear,
    output  wire                            output_valid,
    input   wire                            output_ready,
    output  reg     [WORD_WIDTH_OUTPUT-1:0] output_data
);

//### Buffer Depth Adjustment

// First, we have to calculate the Least Common Multiple (LCM) of both
// `WORD_WIDTH_INPUT` and `WORD_WIDTH_OUTPUT`, which gives us the minimum
// buffer depth which will hold a whole number of input and output items at
// the same time.

    `include "lcm_function.vh"

    localparam BUFFER_DEPTH_MIN = lcm(WORD_WIDTH_OUTPUT, WORD_WIDTH_INPUT); // Least Common Multiple

// However, the LCM depth is not necessarily sufficient to ensure full
// throughput, as it may contain too few of `WORD_WIDTH_INPUT` or
// `WORD_WIDTH_OUTPUT` entries to allow reads and writes to continue without
// stalls while the read and write addresses are synchronized across the input
// and output clock domains.

// Based on the design of the [CDC Word Synchronizer]
// (./CDC_Word_Synchronizer.html), the absolute worst-case latency for
// completing a transfer from one clock domain to the other is 8 clock cycles.
// Thus, we have to contain more than *twice* that number of entries (17) in
// the FIFO buffer to guarantee that there is always a free entry to read and
// write at any time, thus avoiding a stall.

// We calculate the final `BUFFER_DEPTH` by dividing it by the larger of
// `WORD_WIDTH_OUTPUT` and `WORD_WIDTH_INPUT`, taking the ratio of that
// fraction with 17 (fudged up by +1 to compensate for integer division), and
// then multiplying the `BUFFER_DEPTH_MIN` by that amount, thus guaranteeing
// that `BUFFER_DEPTH` >= `17 * max(WORD_WIDTH_INPUT, WORD_WIDTH_OUTPUT)`.

// I do integer division with a +1 fudge factor to avoid potential problems as
// it's unclear if casting a real to an integer truncates or rounds. So lets
// pay the price of possible `BUFFER_DEPTH_MIN` more entries than we really
// need to guarantee we meet our constraint. *This can double the buffer depth
// when the LCM is a large number close to `17 * max(WORD_WIDTH_OUTPUT,
// WORD_WIDTH_INPUT)`.*

    `include "max_function.vh"

    localparam WORD_WIDTH_MAX           = max(WORD_WIDTH_OUTPUT, WORD_WIDTH_INPUT);
    localparam ITEM_COUNT_MIN           = BUFFER_DEPTH_MIN / WORD_WIDTH_MAX;
    localparam BUFFER_DEPTH_MULTIPLIER  = (17 / ITEM_COUNT_MIN) + 1;
    localparam BUFFER_DEPTH             = BUFFER_DEPTH_MIN * BUFFER_DEPTH_MULTIPLIER;

    `include "clog2_function.vh"

    localparam ADDR_WIDTH       = clog2(BUFFER_DEPTH);

    localparam ADDR_ZERO        = {ADDR_WIDTH{1'b0}};
    localparam ADDR_LAST        = BUFFER_DEPTH-1;

    localparam BUFFER_ZERO      = {BUFFER_DEPTH{1'b0}};
    localparam OUTPUT_ZERO      = {WORD_WIDTH_OUTPUT{1'b0}};

    // A little contortion to please the linter.
    // (doing (foo-1)[width-1:0], or similar, isn't legal in Verilog-2001)

    localparam [ADDR_WIDTH-1:0] ADDR_INITIAL_INPUT  = WORD_WIDTH_INPUT  - 1;
    localparam [ADDR_WIDTH-1:0] ADDR_INITIAL_OUTPUT = WORD_WIDTH_OUTPUT - 1;

    initial begin
        input_ready = 1'b1; // Empty at start, so accept data
        output_data = OUTPUT_ZERO;
    end

//## Data Path

//### FIFO Buffer Registers

// We have to access arbitrary word subsets of the entire FIFO storage so we
// can read and write word of different width *without introducing gaps in the
// data!* Block RAMs only support limited and fixed word sizes, so are not
// usable here. Thus, we must implement using registers and read/write the
// necessary exact word subsets as needed.

// We also need to do CDC, so we must be careful to not have simultaneous
// reads and write to the same register.

    reg [BUFFER_DEPTH-1:0] buffer = BUFFER_ZERO;

//### Read/Write Address Counters (Head and Tail)

// To define a word subset inside the `buffer`, the input and output each use
// two counters: head and tail. The tail counter starts at `ADDR_ZERO`, and
// the head counter starts at `WORD_WIDTH_OUTPUT-1` or `WORD_WIDTH_INPUT-1`,
// and both can only increment by `WORD_WIDTH_OUTPUT` or `WORD_WIDTH_INPUT`,
// wrapping around to their start value if incremented past `ADDR_LAST`.

// Since `BUFFER_DEPTH` is the Least Common Multiple of the input/output word
// widths, the counters always index a whole word without residue or having to
// wrap around the end of the buffer.

// We use two counters rather than a counter and an adder to calculate the
// next head and tail concurrently.

// From these counter values we can perform range checks (e.g.: by seeing if
// a write head counter is past a read tail counter, and thus there is word
// overlap and no room to write) to test if there is enough input data to
// compose an output data word, if we have reached the end of the buffer, and
// calculate vector part selects to read/write the buffer.

//#### Write Address Counters

    reg increment_buffer_write_addr = 1'b0;
    reg load_buffer_write_addr      = 1'b0;

    wire [ADDR_WIDTH-1:0] buffer_write_addr_tail;

    Counter_Binary
    #(
        .WORD_WIDTH     (ADDR_WIDTH),
        .INCREMENT      (WORD_WIDTH_INPUT),
        .INITIAL_COUNT  (ADDR_ZERO)
    )
    write_address_tail
    (
        .clock          (input_clock),
        .clear          (input_clear),
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
        .count          (buffer_write_addr_tail)
    );

    wire [ADDR_WIDTH-1:0] buffer_write_addr_head;

    Counter_Binary
    #(
        .WORD_WIDTH     (ADDR_WIDTH),
        .INCREMENT      (WORD_WIDTH_INPUT),
        .INITIAL_COUNT  (ADDR_INITIAL_INPUT)
    )
    write_address_head
    (
        .clock          (input_clock),
        .clear          (input_clear),
        .up_down        (1'b0), // 0/1 --> up/down
        .run            (increment_buffer_write_addr),
        .load           (load_buffer_write_addr),
        .load_count     (ADDR_INITIAL_INPUT),
        .carry_in       (1'b0),
        // verilator lint_off PINCONNECTEMPTY
        .carry_out      (),
        .carries        (),
        .overflow       (),
        // verilator lint_on  PINCONNECTEMPTY
        .count          (buffer_write_addr_head)
    );

//#### Read Address Counters

    reg increment_buffer_read_addr = 1'b0;
    reg load_buffer_read_addr      = 1'b0;

    wire [ADDR_WIDTH-1:0] buffer_read_addr_tail;

    Counter_Binary
    #(
        .WORD_WIDTH     (ADDR_WIDTH),
        .INCREMENT      (WORD_WIDTH_OUTPUT),
        .INITIAL_COUNT  (ADDR_ZERO)
    )
    read_address_tail
    (
        .clock          (output_clock),
        .clear          (output_clear),
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
        .count          (buffer_read_addr_tail)
    );

    wire [ADDR_WIDTH-1:0] buffer_read_addr_head;

    Counter_Binary
    #(
        .WORD_WIDTH     (ADDR_WIDTH),
        .INCREMENT      (WORD_WIDTH_OUTPUT),
        .INITIAL_COUNT  (ADDR_INITIAL_OUTPUT)
    )
    read_address_head
    (
        .clock          (output_clock),
        .clear          (output_clear),
        .up_down        (1'b0), // 0/1 --> up/down
        .run            (increment_buffer_read_addr),
        .load           (load_buffer_read_addr),
        .load_count     (ADDR_INITIAL_OUTPUT),
        .carry_in       (1'b0),
        // verilator lint_off PINCONNECTEMPTY
        .carry_out      (),
        .carries        (),
        .overflow       (),
        // verilator lint_on  PINCONNECTEMPTY
        .count          (buffer_read_addr_head)
    );


//### Wrap-Around Bits

// To distinguish between the empty and full cases, which both identically
// show as equal read and write buffer addresses, we keep track of each time
// an address wraps around to zero by toggling a bit.  *The addresses never
// pass eachother.* 

// If the write address runs ahead of the read address enough to wrap-around
// and reach the read address from behind, the buffer is full (or has less
// free space than one write word) and all writes to the buffer halt until
// after we've read out more than the width of a write word. We detect this
// because the write address will have wrapped-around one more time than the
// read address, so their wrap-around bits will be different.

// Conversely, if the read address catches up to the write address from behind,
// the buffer is empty (or containing less than one read word of data) and all
// reads halt until after we've written enough data to have more than the
// width of a read word in the buffer.  In this case, the wrap-around bits are
// identical.

    reg  toggle_buffer_write_addr_wrap_around = 1'b0;
    wire buffer_write_addr_wrap_around;

    Register_Toggle
    #(
        .WORD_WIDTH     (1),
        .RESET_VALUE    (1'b0)
    )
    write_wrap_around_bit
    (
        .clock          (input_clock),
        .clock_enable   (1'b1),
        .clear          (input_clear),
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
        .clock          (output_clock),
        .clock_enable   (1'b1),
        .clear          (output_clear),
        .toggle         (toggle_buffer_read_addr_wrap_around),
        .data_in        (buffer_read_addr_wrap_around),
        .data_out       (buffer_read_addr_wrap_around)
    );

//### Read/Write Address CDC Transfer

// We need to compare the read and write addresses, along with their
// associated wrap-around bits, to detect if the buffer is holding any items.
// Therefore, we need to transfer the read address into the `output_clock`
// domain, and the write address into the `input_clock` domain. We do this
// with two [CDC Word Synchronizers](./CDC_Word_Synchronizer.html).

// A read/write address is always valid, so we tie `sending_valid` high and
// ignore `sending_ready`. Then, we loop `receiving_valid` into
// `receiving_ready` so we start a new CDC word transfer as soon as the
// current CDC word transfer completes. This configuration samples the address
// continuously, as fast as the CDC word transfer happens. The synchronized
// address at `receiving_data` remains steady between CDC word transfers.

// It takes a few cycles to do the CDC word transfer, so when comparing the
// local read or write address with the synchronized counterpart from the
// other clock domain, we are comparing to a slightly stale version, lagging
// behind the actual value. However, since the addresses never pass eachother,
// this does not cause any corruption. The synchronized value eventually
// catches up, and the actual buffer condition is updated. *At worst, this lag
// means having to specify a somewhat deeper FIFO to achieve the expected peak
// capacity, depending on input/output rates.* However, not being restricted
// to powers-of-two FIFO depths minimizes this overhead.

    wire [ADDR_WIDTH-1:0]   buffer_write_addr_tail_synced;
    wire                    buffer_write_addr_wrap_around_synced;
    wire                    buffer_write_addr_synced_valid;

    CDC_Word_Synchronizer
    #(
        .WORD_WIDTH             (1 + ADDR_WIDTH),
        .EXTRA_CDC_DEPTH        (CDC_EXTRA_STAGES),
        .OUTPUT_BUFFER_TYPE     ("HALF"), // "HALF", "SKID", "FIFO"
        .OUTPUT_BUFFER_CIRCULAR (0),
        .FIFO_BUFFER_DEPTH      (), // Only for "FIFO"
        .FIFO_BUFFER_RAMSTYLE   ()  // Only for "FIFO"
    )
    write_to_read
    (
        .sending_clock          (input_clock),
        .sending_clear          (input_clear),
        .sending_data           ({buffer_write_addr_wrap_around, buffer_write_addr_tail}),
        .sending_valid          (1'b1),
        // verilator lint_off PINCONNECTEMPTY
        .sending_ready          (),
        // verilator lint_on  PINCONNECTEMPTY

        .receiving_clock        (output_clock),
        .receiving_clear        (output_clear),
        .receiving_data         ({buffer_write_addr_wrap_around_synced, buffer_write_addr_tail_synced}),
        .receiving_valid        (buffer_write_addr_synced_valid),
        .receiving_ready        (buffer_write_addr_synced_valid)
    );

    wire [ADDR_WIDTH-1:0]   buffer_read_addr_tail_synced;
    wire                    buffer_read_addr_wrap_around_synced;
    wire                    buffer_read_addr_synced_valid;

    CDC_Word_Synchronizer
    #(
        .WORD_WIDTH             (1+ ADDR_WIDTH),
        .EXTRA_CDC_DEPTH        (CDC_EXTRA_STAGES),
        .OUTPUT_BUFFER_TYPE     ("HALF"), // "HALF", "SKID", "FIFO"
        .OUTPUT_BUFFER_CIRCULAR (0),
        .FIFO_BUFFER_DEPTH      (), // Only for "FIFO"
        .FIFO_BUFFER_RAMSTYLE   ()  // Only for "FIFO"
    )
    read_to_write
    (
        .sending_clock          (output_clock),
        .sending_clear          (output_clear),
        .sending_data           ({buffer_read_addr_wrap_around, buffer_read_addr_tail}),
        .sending_valid          (1'b1),
        // verilator lint_off PINCONNECTEMPTY
        .sending_ready          (),
        // verilator lint_on  PINCONNECTEMPTY

        .receiving_clock        (input_clock),
        .receiving_clear        (input_clear),
        .receiving_data         ({buffer_read_addr_wrap_around_synced, buffer_read_addr_tail_synced}),
        .receiving_valid        (buffer_read_addr_synced_valid),
        .receiving_ready        (buffer_read_addr_synced_valid)
    );


//## Control Path

//### Buffer States

// We describe the state of the buffer itself as the number of items currently
// stored in the buffer, as indicated by the read and write addresses and
// their wrap-around bits. We only care about the extremes: 

// * if the buffer holds no read words, or less than one read word, thus we cannot read
// * if the buffer holds its maximum number of write words, or has less free space than one write word, thus we cannot write

    reg cannot_read  = 1'b0;
    reg cannot_write = 1'b0;

    always @(*) begin
        cannot_read  = (buffer_read_addr_head        > buffer_write_addr_tail_synced) && (buffer_read_addr_wrap_around        == buffer_write_addr_wrap_around_synced);
        cannot_write = (buffer_read_addr_tail_synced < buffer_write_addr_head)        && (buffer_read_addr_wrap_around_synced != buffer_write_addr_wrap_around);
    end

//### Input Interface (Insert)

// The input interface is simple: if the buffer isn't at its maximum capacity,
// signal the input is ready, and when an input handshake completes, write the
// data directly into the buffer and increment the write address, wrapping
// around as necessary.

    reg insert = 1'b0;

    always @(*) begin
        input_ready                             = (cannot_write == 1'b0);
        insert                                  = (input_valid  == 1'b1) && (input_ready  == 1'b1);
        increment_buffer_write_addr             = (insert == 1'b1);
        load_buffer_write_addr                  = (increment_buffer_write_addr == 1'b1) && (buffer_write_addr_head == ADDR_LAST [ADDR_WIDTH-1:0]);
        toggle_buffer_write_addr_wrap_around    = (load_buffer_write_addr      == 1'b1);
    end

// Normally this would be a Register module, but we need to describe a clock
// enable to *part* of the registers here, not a data mux. So it's a rare use
// of an if-statement outside of a generate block.

    always @(posedge input_clock) begin
        if (insert == 1'b1) begin
            buffer [buffer_write_addr_tail +: WORD_WIDTH_INPUT] <= input_data;
        end
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
        output_leaving_idle                 = (output_valid == 1'b0) && (cannot_read         == 1'b0);
        load_output_register                = (remove       == 1'b1) || (output_leaving_idle == 1'b1);

        increment_buffer_read_addr          = (load_output_register       == 1'b1) && (cannot_read  == 1'b0);
        load_buffer_read_addr               = (increment_buffer_read_addr == 1'b1) && (buffer_read_addr_head  == ADDR_LAST [ADDR_WIDTH-1:0]);
        toggle_buffer_read_addr_wrap_around = (load_buffer_read_addr      == 1'b1);
    end

// Normally this would be a Register module, but we need to describe a clock
// enable to the `output_data` register, and a mux from the buffer. So it's
// a rare use of an if-statement outside of a generate block.

    always @(posedge output_clock) begin
        if (load_output_register == 1'b1) begin
            output_data <= buffer [buffer_read_addr_tail +: WORD_WIDTH_OUTPUT];
        end
    end

// `output_valid` must be registered to match the latency of the buffer output
// register.

    Register
    #(
        .WORD_WIDTH     (1),
        .RESET_VALUE    (1'b0)
    )
    output_data_valid
    (
        .clock          (output_clock),
        .clock_enable   (load_output_register == 1'b1),
        .clear          (output_clear),
        .data_in        (cannot_read == 1'b0),
        .data_out       (output_valid)
    );

endmodule

