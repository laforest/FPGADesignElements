//# Multi-Ported RAM using Logic Elements

// Implements a memory with multiple, concurrent read and write ports with
// optionally pipelined reads and multiple write conflict handling strategies.
// Storage is implemented using logic elements and registers.

//## Scaling and Applications

// This kind of multi-ported memory is not expected to map to underlying RAM
// blocks, but it can support arbitrary numbers of read and write ports by
// using random logic and registers, *and can be bulk-cleared in a single
// cycle*. It will not scale well to large depths or widths, but it is
// suitable for small, highly-concurrent memories such as semaphores, small
// CPU register files, or storage for parallel functional units, and is the
// building block of more efficient, larger multi-ported memories.

//## Concurrency and Write Conflicts

// Concurrent reads and a single, non-conflicting write to the same address
// always returns the currently stored data, not the data being written, which
// becomes readable in the next cycle.

// The result of concurrent writes to the same address is defined by the
// `ON_WRITE_CONFLICT` parameter, which specifies how to combine or filter
// conflicting writes. If a write port conflicts with another, its
// `write_conflict` bit is raised for one cycle in the cycle after the write.

// * PRIORITY: The lowest conflicting write port wins. The other conflicting
// writes do nothing and have their `write_conflict` signal raised for one
// cycle after the write.
// * ROUNDROBIN: The lowest conflicting write port wins, and served in
// round-robin order. The other conflicting writes do nothing and have their
// `write_conflict` signal raised for one cycle after the write.
// * DISCARD: All conflicting writes do nothing, and have their
// `write_conflict` signal raised for one cycle after the write.
// * AND/OR/XOR/NAND/NOR/XNOR: The data from conflicting writes is combined
// using the specified Boolean operation, and have their `write_conflict`
// signal raised for one cycle after the write.

//## Synthesis Parameters

// The `RAMSTYLE` parameter is still provided for cases where the CAD tool
// might be able to map to RAM blocks, such as when `WRITE_PORT_COUNT` is 1.
// However, write-forwarding is not supported, unlike the [Simple Dual Port
// RAM](./RAM_Simple_Dual_Port.html), for example. 

// Expect warnings from the linter and your CAD tools if `DEPTH` is less than
// `ADDR_WIDTH**2`. It is allowable: *out-of-bounds reads and writes
// will respectively return zero and have no effect on the stored data.*
// Out-of-bounds writes cannot cause write conflicts.

// The `READ_PIPELINE_DEPTH` parameter defines how many pipeline stages are
// placed between the storage and the read port multiplexer, for eventual
// retiming.  A read pipeline improves clock speed at the expense of read
// latency. Note that a written value is still readable on the next cycle
// after the write, but it will then take `READ_PIPELINE_DEPTH` extra cycles
// for that read to complete. Reads may be pipelined one after another, and
// you must externally keep track of the constant latency between raising
// `read_enable` and reading out the corresponding data.

//## Parameters, Ports, and Constants

// Since we cannot have variable numbers of ports on a Verilog module, the
// read and write data, address, and enable ports are vectors which
// concatenate all the read/write ports in numerical order. Each individual
// read/write port behaves like every other read/write port. There is no
// distinction, except perhaps in write conflict resolution.

`default_nettype none

module RAM_Multiported_LE
#(
    parameter                       WORD_WIDTH          = 0,
    parameter                       READ_PORT_COUNT     = 0,
    parameter                       WRITE_PORT_COUNT    = 0,
    parameter                       ADDR_WIDTH          = 0,
    parameter                       DEPTH               = 0,
    parameter                       USE_INIT_FILE       = 0,
    parameter                       INIT_FILE           = "",
    parameter   [WORD_WIDTH-1:0]    INIT_VALUE          = 0,
    // The usage in attributes is not seen by the linter.
    // verilator lint_off UNUSED
    parameter                       RAMSTYLE            = "",
    // verilator lint_on  UNUSED
    parameter                       ON_WRITE_CONFLICT   = "",
    parameter                       READ_PIPELINE_DEPTH = 0,

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
    output  wire    [WRITE_PORT_COUNT-1:0]  write_conflict,

    output  wire    [TOTAL_READ_DATA-1:0]   read_data,
    input   wire    [TOTAL_READ_ADDR-1:0]   read_address,
    input   wire    [READ_PORT_COUNT-1:0]   read_enable
);

    localparam ADDR_ZERO                = {ADDR_WIDTH{1'b0}};
    localparam WRITE_ADDR_HIT_ZERO      = {WRITE_PORT_COUNT{1'b0}};
    localparam WRITE_ROUNDROBIN_NOMASK  = {WRITE_PORT_COUNT{1'b1}};
    localparam WRITE_ADDR_HIT_ONE       = {{WRITE_PORT_COUNT-1{1'b0}},1'b1};
    localparam TOTAL_STORED_DATA        = WORD_WIDTH * DEPTH;
    localparam TOTAL_STORED_ZERO        = {TOTAL_STORED_DATA{1'b0}};
    localparam WRITE_CONFLICT_WIDTH     = WRITE_PORT_COUNT * DEPTH;
    localparam WRITE_CONFLICT_ZERO      = {WRITE_CONFLICT_WIDTH{1'b0}};

//## RAM Array

// CAD tools expect a memory description like this, an arrays of registers, to
// infer RAM and to enable initializing from a file. The CAD tool will *try*
// to map the memory to the specified `RAMSTYLE`, but unless your device has
// unusual RAM blocks, this will map to general logic registers.

    (* ramstyle  = RAMSTYLE *) // Quartus
    (* ram_style = RAMSTYLE *) // Vivado

    reg [WORD_WIDTH-1:0] ram [DEPTH-1:0];

//## Write Ports and Conflicts

// For each `ram` array location, decode the `write_address` from each write
// port, masked by each write port's `write_enable` bit. If an address
// matches, then store the write data from that write port into that `ram`
// array location. Conflicting writes are handled as specified by the
// `ON_WRITE_CONFLICT` parameter.

// If no write address matches the `ram` location, then no write is enabled to
// that `ram` location.  Thus, if the write address exceeds the `DEPTH` of the
// `ram`, nothing happens. You will have to detect this situation externally
// by comparing `write_address` with `DEPTH` using an [Arithmetic
// Predicates](./Arithmetic_Predicates_Binary.html) module.

    generate
    genvar i, j;

        reg [TOTAL_STORED_DATA-1:0]     stored_data         = TOTAL_STORED_ZERO;
        reg [WRITE_CONFLICT_WIDTH-1:0]  write_conflict_all  = WRITE_CONFLICT_ZERO;

        for (i=0; i < DEPTH; i=i+1) begin: per_ram_unit

// First, we decode the address from each write port to each ram unit.

            wire [WRITE_PORT_COUNT-1:0] write_addr_hit;

            for (j=0; j < WRITE_PORT_COUNT; j=j+1) begin: per_write_port
                Address_Decoder_Behavioural
                #(
                    .ADDR_WIDTH (ADDR_WIDTH)
                )
                write_address_decoder
                (
                    .base_addr  (i [ADDR_WIDTH-1:0]), // Must trim ram unit address to width to avoid linter warnings.
                    .bound_addr (i [ADDR_WIDTH-1:0]),
                    .addr       (write_address [ADDR_WIDTH*j +: ADDR_WIDTH]),
                    .hit        (write_addr_hit [j])
                );
            end

// We then mask-off not-enabled write ports: they cannot cause conflicts,
// regardless of their `write_address`.

            reg [WRITE_PORT_COUNT-1:0] write_addr_hit_enabled = WRITE_ADDR_HIT_ZERO;

            always @(*) begin
                write_addr_hit_enabled = write_addr_hit & write_enable;
            end

// Then detect write conflicts by counting the number of writes to this ram
// unit. There's only two cases, so rather than doing an arithmetic
// comparison, we can simply enumerate them as equality checks: when not only
// one port is writing to this ram unit, and when that number is non-zero.

            wire [WRITE_PORT_COUNT-1:0] write_addr_hit_count;

            Population_Count
            #(
                .WORD_WIDTH (WRITE_PORT_COUNT)
            )
            detect_multiple_writes
            (
                .word_in    (write_addr_hit_enabled),
                .count_out  (write_addr_hit_count)
            );

            reg write_conflict_raw = 1'b0;

            always @(*) begin
                write_conflict_raw = (write_addr_hit_count != WRITE_ADDR_HIT_ONE) && (write_addr_hit_count != WRITE_ADDR_HIT_ZERO);
            end

// Copy the vector of write address hits for later calculation of all write
// conflicts. If there is no conflict, then mask off this ram location's write
// address hits from the conflict calculations.

            wire [WRITE_PORT_COUNT-1:0] write_conflict_ports;

            Annuller
            #(
                .WORD_WIDTH     (WRITE_PORT_COUNT),
                .IMPLEMENTATION ("AND")
            )
            write_conflicts_masker
            (
                .annul          (write_conflict_raw == 1'b0),
                .data_in        (write_addr_hit_enabled),
                .data_out       (write_conflict_ports)
            );

//### Write Conflict Handling

// Here are the various write conflict handling strategies. For each, we
// decide if the ram location is enabled for write, and which data to write to
// it. We may also update the list of conflicting writes if a conflict
// resolves down to one write winning.

            reg                         write_enable_ram = 1'b0;
            wire [WORD_WIDTH-1:0]       write_data_selected;
            reg  [WRITE_PORT_COUNT-1:0] write_conflict_ports_masked = WRITE_ADDR_HIT_ZERO;

//#### PRIORITY

// Mask off the write address conflict of the winning port if there is
// a conflict, and select its data to write.  The winning port is the lowest
// numbered port of the conflicting ports, as calculated by a Priority Arbiter.

            // verilator lint_off WIDTH
            if (ON_WRITE_CONFLICT == "PRIORITY") begin
            // verilator lint_on  WIDTH

                wire [WRITE_PORT_COUNT-1:0] write_addr_hit_masked_priority;

                Arbiter_Priority
                #(
                    .INPUT_COUNT    (WRITE_PORT_COUNT)
                )
                write_data_priority
                (
                    .requests       (write_addr_hit_enabled),
                    .grant          (write_addr_hit_masked_priority)
                );

                always @(*) begin
                    write_conflict_ports_masked = write_conflict_ports & ~write_addr_hit_masked_priority;
                    write_enable_ram            = write_addr_hit_enabled != WRITE_ADDR_HIT_ZERO;
                end

                Multiplexer_One_Hot
                #(
                    .WORD_WIDTH     (WORD_WIDTH),
                    .WORD_COUNT     (WRITE_PORT_COUNT),
                    .OPERATION      ("OR"),
                    .IMPLEMENTATION ("AND")
                )
                write_data_mux_priority
                (
                    .selectors      (write_addr_hit_masked_priority),
                    .words_in       (write_data),
                    .word_out       (write_data_selected)
                );

//#### ROUNDROBIN

// Mask off the write address conflict of the winning port if there is
// a conflict, and select its data to write.  The winning port is the lowest
// numbered port of the conflicting ports which is waiting for a write, as
// calculated by a Round-Robin Arbiter.

            // verilator lint_off WIDTH
            end else if (ON_WRITE_CONFLICT == "ROUNDROBIN") begin
            // verilator lint_on  WIDTH

                wire [WRITE_PORT_COUNT-1:0] write_addr_hit_masked_roundrobin;

                Arbiter_Round_Robin
                #(
                    .INPUT_COUNT    (WRITE_PORT_COUNT)
                )
                write_data_round_robin
                (
                    .clock          (clock),
                    .clear          (clear),

                    .requests       (write_addr_hit_enabled),
                    .requests_mask  (WRITE_ROUNDROBIN_NOMASK), // Set to all-ones if unused.
                    // verilator lint_off PINCONNECTEMPTY
                    .grant_previous (),
                    // verilator lint_on  PINCONNECTEMPTY
                    .grant          (write_addr_hit_masked_roundrobin)
                );

                always @(*) begin
                    write_conflict_ports_masked = write_conflict_ports & ~write_addr_hit_masked_roundrobin;
                    write_enable_ram            = write_addr_hit_enabled != WRITE_ADDR_HIT_ZERO;
                end

                Multiplexer_One_Hot
                #(
                    .WORD_WIDTH     (WORD_WIDTH),
                    .WORD_COUNT     (WRITE_PORT_COUNT),
                    .OPERATION      ("OR"),
                    .IMPLEMENTATION ("AND")
                )
                write_data_mux_roundrobin
                (
                    .selectors      (write_addr_hit_masked_roundrobin),
                    .words_in       (write_data),
                    .word_out       (write_data_selected)
                );

//#### DISCARD

// If there is a conflict, all conflicting writes are disabled. Their data is
// lost. Otherwise, the data from the single, non-conflicting write to this
// ram unit, is selected and written.

            // verilator lint_off WIDTH
            end else if (ON_WRITE_CONFLICT == "DISCARD") begin
            // verilator lint_on  WIDTH

                always @(*) begin
                    write_conflict_ports_masked = write_conflict_ports;
                    write_enable_ram            = write_addr_hit_count == WRITE_ADDR_HIT_ONE;
                end

                Multiplexer_One_Hot
                #(
                    .WORD_WIDTH     (WORD_WIDTH),
                    .WORD_COUNT     (WRITE_PORT_COUNT),
                    .OPERATION      ("OR"), // Data never used under conflict. Could be any operation.
                    .IMPLEMENTATION ("AND")
                )
                write_data_mux_discard
                (
                    .selectors      (write_addr_hit_enabled),
                    .words_in       (write_data),
                    .word_out       (write_data_selected)
                );

//#### AND/OR/XOR/NAND/NOR/XNOR

// Otherwise, by default, the data from conflicting writes, if any, is reduced
// to a single word via the specified Boolean reduction operator.

            end else begin

                always @(*) begin
                    write_conflict_ports_masked = write_conflict_ports;
                    write_enable_ram            = write_addr_hit_enabled != WRITE_ADDR_HIT_ZERO;
                end

                Multiplexer_One_Hot
                #(
                    .WORD_WIDTH     (WORD_WIDTH),
                    .WORD_COUNT     (WRITE_PORT_COUNT),
                    .OPERATION      (ON_WRITE_CONFLICT),
                    .IMPLEMENTATION ("AND")
                )
                write_data_mux_boolean
                (
                    .selectors      (write_addr_hit_enabled),
                    .words_in       (write_data),
                    .word_out       (write_data_selected)
                );

            end

// Finally, add the address hits to the global list of all write conflicts
// (one bit per write port, repeated for each ram location).

            always @(*) begin
                write_conflict_all [WRITE_PORT_COUNT*i +: WRITE_PORT_COUNT] = write_conflict_ports_masked;
            end

//### Storage

// Rather than use a [Register](./Register.html) module for each `ram`
// location, we copy the register logic directly here, since we
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

//### Report Write Conflicts

// Here, we reduce and store all the possible write conflicts from each write
// port at each ram unit into a single bit for each write port which indicates
// if the last write conflicted with another.

    wire [WRITE_PORT_COUNT-1:0] write_conflict_merged;

    Word_Reducer
    #(
        .OPERATION  ("OR"),
        .WORD_WIDTH (WRITE_PORT_COUNT),
        .WORD_COUNT (DEPTH)
    )
    write_conflict_merge
    (
        .words_in   (write_conflict_all),
        .word_out   (write_conflict_merged)
    );

    Register
    #(
        .WORD_WIDTH     (WRITE_PORT_COUNT),
        .RESET_VALUE    (WRITE_ADDR_HIT_ZERO)
    )
    write_conflict_storage
    (
        .clock          (clock),
        .clock_enable   (1'b1),
        .clear          (clear),
        .data_in        (write_conflict_merged),
        .data_out       (write_conflict)
    );

//## Read Ports

// For each read port, we use the `read_address` to select the desired data
// word, and register it as output if `read_enable` is set that cycle. If the
// `read_address` is greater than the `ram` `DEPTH`, then `read_data` returns
// zero (and such an out-of-bounds access could also be detected here by
// comparing the address to `DEPTH`).

    generate
    genvar k;

        for (k=0; k < READ_PORT_COUNT; k=k+1) begin: per_read_port

            wire [ADDR_WIDTH-1:0]           read_port_address_captured;
            wire [ADDR_WIDTH-1:0]           read_port_address_pipelined;
            wire [TOTAL_STORED_DATA-1:0]    stored_data_captured;
            wire [TOTAL_STORED_DATA-1:0]    stored_data_pipelined;

            if (READ_PIPELINE_DEPTH == 0) begin
                assign read_port_address_captured  = read_address [ADDR_WIDTH*k +: ADDR_WIDTH];
                assign read_port_address_pipelined = read_port_address_captured;
                assign stored_data_captured        = (read_enable [k] == 1'b1) ? stored_data : TOTAL_STORED_ZERO;
                assign stored_data_pipelined       = stored_data_captured;
            end

// If there is at least one state of read pipelining, then the first stage
// registers a copy of all the stored data, and that read port's address, if
// that read port is enabled.

            if (READ_PIPELINE_DEPTH >= 1) begin

                Register
                #(
                    .WORD_WIDTH     (ADDR_WIDTH),
                    .RESET_VALUE    (ADDR_ZERO)
                )
                capture_read_address
                (
                    .clock          (clock),
                    .clock_enable   (read_enable [k]),
                    .clear          (clear),
                    .data_in        (read_address [ADDR_WIDTH*k +: ADDR_WIDTH]),
                    .data_out       (read_port_address_captured)
                );
            
                Register
                #(
                    .WORD_WIDTH     (TOTAL_STORED_DATA),
                    .RESET_VALUE    (TOTAL_STORED_ZERO)
                )
                capture_stored_data
                (
                    .clock          (clock),
                    .clock_enable   (read_enable [k]),
                    .clear          (clear),
                    .data_in        (stored_data),
                    .data_out       (stored_data_captured)
                );
            
            end

// If there is exactly one read pipeline stage, then we are done. Copy the
// registered read data and address along to the final multiplexer.

            if (READ_PIPELINE_DEPTH == 1) begin
                assign read_port_address_pipelined = read_port_address_captured;
                assign stored_data_pipelined       = stored_data_captured;
            end

// If there is more than one read pipeline stage, then add them here, after
// the first, enabled stage. These stages have no control signals to make
// their retiming into the multiplexer easy, so data always moves here.

            if (READ_PIPELINE_DEPTH > 1) begin

                Register_Pipeline_Simple
                #(
                    .WORD_WIDTH     (ADDR_WIDTH),
                    .PIPE_DEPTH     (READ_PIPELINE_DEPTH-1)
                )
                pipeline_read_address
                (
                    .clock          (clock),
                    .clock_enable   (1'b1),
                    .clear          (1'b0),
                    .pipe_in        (read_port_address_captured),
                    .pipe_out       (read_port_address_pipelined)
                );

                Register_Pipeline_Simple
                #(
                    .WORD_WIDTH     (TOTAL_STORED_DATA),
                    .PIPE_DEPTH     (READ_PIPELINE_DEPTH-1)
                )
                pipeline_stored_data
                (
                    .clock          (clock),
                    .clock_enable   (1'b1),
                    .clear          (1'b0),
                    .pipe_in        (stored_data_captured),
                    .pipe_out       (stored_data_pipelined)
                );

            end

// Finally, select the read data word specified by the read address of this
// read port.

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
                .selector       (read_port_address_pipelined),
                .words_in       (stored_data_pipelined),
                .word_out       (read_data [WORD_WIDTH*k +: WORD_WIDTH])
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

