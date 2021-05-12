//# Multi-Ported RAM using Logic Elements (Structural Implementation)

// Implements a memory with multiple read and write ports which can all be
// used concurrently, implemented using logic elements, structurally described
// using decoders and multiplexers.

// This implementation describes the logic in a structural manner, built from
// known sub-modules which can all be directly ported to any other HDL, rather
// than depend on Verilog-specific features as in the [behavioural
// implementation](./RAM_Multiported_LE_Behavioural.html), at the cost of
// larger logic (but the same number of registers). The structural
// implementation also makes the operation under write-conflicts and
// out-of-bounds accesses well-defined, and easy to change as necessary for
// your application. 

//## Synthesis and Operation

// This kind of multi-ported memory is not expected to map to underlying RAM
// blocks, but it can support arbitrary numbers of read and write ports by
// using random logic and registers, *and can be bulk-cleared in a single
// cycle*. It will not scale well to large depths or widths, and become very
// large and slow. But it is suitable for small, highly-concurrent memories
// such as semaphores, small CPU register files, or storage for parallel
// functional units, and is the building block of more efficient, larger
// multi-ported memories.

// The `RAMSTYLE` parameter is still provided for cases where the CAD tool
// might be able to map to RAM blocks, such as when `WRITE_PORT_COUNT` is 1.
// However, write-forwarding is not supported, unlike the [Simple Dual Port
// RAM](./RAM_Simple_Dual_Port.html), for example. 

// Expect warnings from the linter and your CAD tools if `DEPTH` is less than
// `ADDR_WIDTH**2`. It is allowable: *out-of-bounds reads and writes
// will respectively return zero and have no effect on the stored data.*

// Concurrent reads and writes to the same address always returns the
// currently stored data, not the data being written, which becomes readable
// in the next cycle.  The result of concurrent writes to the same address is
// defined by the `ON_WRITE_CONFLICT` parameter, which specifies the Boolean
// combination of the conflicting data writes to the same address.

//## Parameters, Ports, and Constants

// Since we cannot have variable numbers of ports on a Verilog module, the
// read and write data, address, and enable ports are vectors which
// concatenate all the read/write ports in numerical order. Each individual
// read/write port behaves like every other read/write port. There is no
// distinction.

`default_nettype none

module RAM_Multiported_LE_Structural
#(
    parameter                       WORD_WIDTH          = 0,
    parameter                       READ_PORT_COUNT     = 0,
    parameter                       WRITE_PORT_COUNT    = 0,
    parameter                       ADDR_WIDTH          = 0,
    parameter                       DEPTH               = 0,
    parameter                       USE_INIT_FILE       = 0,
    parameter                       INIT_FILE           = "",
    parameter   [WORD_WIDTH-1:0]    INIT_VALUE          = 0,
    parameter                       RAMSTYLE            = "",
    parameter                       ON_WRITE_CONFLICT   = "", // e.g.: AND, OR, XOR, XNOR, etc...

    // Do not set at instantiation, except in IPI
    parameter TOTAL_READ_DATA  = WORD_WIDTH * READ_PORT_COUNT,
    parameter TOTAL_WRITE_DATA = WORD_WIDTH * WRITE_PORT_COUNT,
    parameter TOTAL_READ_ADDR  = ADDR_WIDTH * READ_PORT_COUNT,
    parameter TOTAL_WRITE_ADDR = ADDR_WIDTH * WRITE_PORT_COUNT
)
(
    input   wire                            clock,
    input   wire                            clear,

    input   wire    [TOTAL_WRITE_DATA-1:0]  write_data,
    input   wire    [TOTAL_WRITE_ADDR-1:0]  write_address,
    input   wire    [WRITE_PORT_COUNT-1:0]  write_enable,

    output  wire    [TOTAL_READ_DATA-1:0]   read_data,
    input   wire    [TOTAL_READ_ADDR-1:0]   read_address,
    input   wire    [READ_PORT_COUNT-1:0]   read_enable
);

    localparam WORD_ZERO            = {WORD_WIDTH{1'b0}};
    localparam WRITE_ADDR_HIT_ZERO  = {WRITE_PORT_COUNT{1'b0}};
    localparam TOTAL_STORED_DATA    = WORD_WIDTH * DEPTH;
    localparam TOTAL_STORED_ZERO    = {TOTAL_STORED_DATA{1'b0}};

//## RAM Array

// CAD tools expect a memory description like this, an arrays of registers, to
// infer RAM and to enable initializing from a file. The CAD tool will *try*
// to map the memory to the specified `RAMSTYLE`.

    (* ramstyle  = RAMSTYLE *) // Quartus
    (* ram_style = RAMSTYLE *) // Vivado

    reg [WORD_WIDTH-1:0] ram [DEPTH-1:0];

//## Write Ports and Storage

// For each `ram` array location, decode the `write_address` from each write
// port, masked by each write port's `write_enable` bit. If an address
// matches, then store the write data from that write port into that `ram`
// array location.  If no write address matches the `ram` location, then no
// write is enabled to that `ram` location.  Thus, if the write address
// exceeds the depth of the `ram`, nothing happens.  Conflicting write data
// are merged via the Boolean operation specified by `ON_WRITE_CONFLICT`.

    generate
    genvar i, j;

        reg [TOTAL_STORED_DATA-1:0] stored_data = TOTAL_STORED_ZERO;

        for (i=0; i < DEPTH; i=i+1) begin: per_ram_unit

//### Option: Out-Of-Bounds Write Handling

// By calculating [arithmetic predicates](./Arithmetic_Predicates_Binary.html)
// here to compare the write address with `DEPTH`, you could detect
// out-of-bounds writes.

            wire [WRITE_PORT_COUNT-1:0] write_addr_hit;

            for (j=0; j < WRITE_PORT_COUNT; j=j+1) begin: per_write_port
                Address_Decoder_Behavioural
                #(
                    .ADDR_WIDTH (ADDR_WIDTH)
                )
                write_address_decoder
                (
                    .base_addr  (i [ADDR_WIDTH-1:0]), // Must trim to width to avoid lint warnings.
                    .bound_addr (i [ADDR_WIDTH-1:0]),
                    .addr       (write_address [ADDR_WIDTH*j +: ADDR_WIDTH]),
                    .hit        (write_addr_hit [j])
                );
            end

//### Option: Write Conflict Handling

// Here we compute the final write enable to this particular `ram` location.
// This is where you would handle conflicting writes, by using a [Priority
// Arbiter](./Arbiter_Priority.html) for example. Or maybe return an error
// signal or delay a ready/valid handshake from completing. Or store the
// conflicting writes into a queue, or report the conflict as metadata when
// reading out, etc...

            reg write_enable_ram = 1'b0;

            always @(*) begin
                write_enable_ram = ((write_addr_hit & write_enable) != WRITE_ADDR_HIT_ZERO);
            end

            wire [WORD_WIDTH-1:0] write_data_selected;

            Multiplexer_One_Hot
            #(
                .WORD_WIDTH     (WORD_WIDTH),
                .WORD_COUNT     (WRITE_PORT_COUNT),
                .OPERATION      (ON_WRITE_CONFLICT),
                .IMPLEMENTATION ("AND")
            )
            write_data_mux
            (
                .selectors      (write_addr_hit),
                .words_in       (write_data),
                .word_out       (write_data_selected)
            );

//### Storage

// Rather than use a [Register](./Register.html) module for each `ram`
// location, we implement the writing and reset logic directly here, since we
// *must* use a reg array to enable initializing `ram` from a file later on.
// This code uses the ["Last Assignment Wins"](./verilog.html#resets) reset
// idiom.

            always @(posedge clock) begin
                if (write_enable_ram == 1'b1) begin
                    ram [i] <= write_data_selected;
                end
                if (clear == 1'b1) begin
                    ram [i] <= INIT_VALUE;
                end
            end

//### Flattening

// Here, we flatten the outputs of the `ram` reg array into a single vector so
// each read port can later select the desired data word. This isn't strictly
// necessary, but a single multiplexer is more modular than nested loops
// iterating over each memory location for each read port. 

            always @(*) begin
                stored_data [WORD_WIDTH*i +: WORD_WIDTH] = ram [i];
            end

        end

    endgenerate

//## Read Ports

// For each read port, we use the `read_address` to select the desired data
// word, and register it as output if `read_enable` is set that cycle. If the
// `read_address` is greater than the `ram` `DEPTH`, then `read_data` returns
// zero (and such an out-of-bounds access could also be detected here).

    generate
    genvar k;

        wire [TOTAL_READ_DATA-1:0] read_data_internal;

        for (k=0; k < READ_PORT_COUNT; k=k+1) begin: per_read_port
            Multiplexer_Binary_Structural
            #(
                .WORD_WIDTH     (WORD_WIDTH),
                .ADDR_WIDTH     (ADDR_WIDTH),
                .INPUT_COUNT    (DEPTH),
                .OPERATION      ("OR"),
                .IMPLEMENTATION ("AND")
            )
            read_data_selector
            (
                .selector       (read_address [ADDR_WIDTH*k +: ADDR_WIDTH]),
                .words_in       (stored_data),
                .word_out       (read_data_internal [WORD_WIDTH*k +: WORD_WIDTH])
            );

// The output is registered to match the behaviour of synchronous RAMs, but
// also to pipeline the above *large* multiplexers.

            Register
            #(
                .WORD_WIDTH     (WORD_WIDTH),
                .RESET_VALUE    (WORD_ZERO)
            )
            read_port_output
            (
                .clock          (clock),
                .clock_enable   (read_enable [k]),
                .clear          (clear),
                .data_in        (read_data_internal [WORD_WIDTH*k +: WORD_WIDTH]),
                .data_out       (read_data          [WORD_WIDTH*k +: WORD_WIDTH])
            );
        end

    endgenerate

//## Memory Initialization

// If you are not using an init file, the following code will set all memory
// locations to INIT_VALUE. The CAD tool should generate a memory
// initialization file from that.  This is useful to cleanly zero-out memory
// without having to deal with an init file.  Your CAD tool may complain about
// too many for-loop iterations if your memory is very deep. Adjust the tool
// settings to allow more loop iterations.

// At a minimum, the initialization file format is one value per line, one for
// each memory word from 0 to DEPTH-1, in bare hexadecimal (e.g.: 0012 to init
// a 16-bit memory word with 16'h12). Note that if your WORD_WIDTH isn't
// a multiple of 4, the CAD tool may complain about the width mismatch.
// You can base yourself on this Python [memory initialization file
// generator](./RAM_generate_empty_init_file.py).

    generate
        if (USE_INIT_FILE == 0) begin
            integer l;
            initial begin
                for (l=0; l < DEPTH; l=l+1) begin: per_ram_word
                    ram[l] = INIT_VALUE;
                end
            end
        end
        else begin
            initial begin
                $readmemh(INIT_FILE, ram);
            end
        end
    endgenerate

endmodule

