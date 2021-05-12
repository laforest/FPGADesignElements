//# Multi-Ported RAM using Logic Elements (Behavioural Implementation)

// Implements a memory with multiple read and write ports which can all be
// used concurrently, implemented using logic elements, as behaviourally
// inferred and synthesized by the CAD tool.

// This implementation relies on Verilog-specific behaviour and on the CAD
// tool's ability to synthesize it. Thus, the code is concise, and the
// resulting logic optimally small, but the exact synthesis and behaviour
// under write-conflicts and out-of-bounds accesses is undefined. See the
// [structural implementation](./RAM_Multiported_LE_Structural.html) for
// a version which is more independent of HDL behaviour and CAD tool
// synthesis, and whose behaviour can be controlled and extended.

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
// `ADDR_WIDTH**2`. It is allowable, *but if the given address
// exceeds `DEPTH`, it's unknown if you will access a different memory
// location, or if the access will do nothing*. **Check your synthesis
// results.**

// Concurrent reads and writes to the same address always returns the
// currently stored data, not the data being written. The new written value
// will be readable in the next cycle.  The result of concurrent writes to the
// same address is undefined. Check your synthesis results.

//## Parameters, Ports, and Constants

// Since we cannot have variable numbers of ports on a Verilog module, the
// read and write data, address, and enable ports are vectors which
// concatenate all the read/write ports in numerical order. Each individual
// read/write port behaves like every other read/write port. There is no
// distinction.

`default_nettype none

module RAM_Multiported_LE_Behavioural
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

    output  reg     [TOTAL_READ_DATA-1:0]   read_data,
    input   wire    [TOTAL_READ_ADDR-1:0]   read_address,
    input   wire    [READ_PORT_COUNT-1:0]   read_enable
);

    localparam TOTAL_READ_ZERO    = {TOTAL_READ_DATA{1'b0}};

    initial begin
        read_data = TOTAL_READ_ZERO;
    end

//## RAM Array

// CAD tools expect a memory description like this, an arrays of registers, to
// infer RAM and to enable initializing from a file. The CAD tool will *try*
// to map the memory to the specified `RAMSTYLE`.

    (* ramstyle  = RAMSTYLE *) // Quartus
    (* ram_style = RAMSTYLE *) // Vivado

    reg [WORD_WIDTH-1:0] ram [DEPTH-1:0];

//## Implementation Issues

// This is one of the few places where using if-statements is necessary
// instead of ternary operators, for RAM inference by the CAD tool.  This code
// also uses the ["Last Assignment Wins"](./verilog.html#resets) reset idiom.

// Although the following code is direct and concise, you need to know how the
// underlying Verilog event queue works for non-blocking assignments to
// understand it fully, and that is something to avoid when writing Verilog
// code. Also, the synthesis of the implicit multiplexers and address decoders
// is not evident from this code, nor controllable, and it would be difficult
// to add more complex behaviour such as handling write conflicts. 

//## Write Ports

    integer i, j;

    always @(posedge clock) begin
        for (i=0; i < WRITE_PORT_COUNT; i=i+1) begin: per_write_port
            if (write_enable[i] == 1'b1) begin
                ram [write_address [ADDR_WIDTH*i +: ADDR_WIDTH]] <= write_data [WORD_WIDTH*i +: WORD_WIDTH];
            end
        end
        for (j=0; j < DEPTH; j=j+1) begin: per_ram_reset
            if (clear == 1'b1) begin
                ram [j] <= INIT_VALUE;
            end
        end
    end

//## Read Ports

    integer k, l;

    always @(posedge clock) begin
        for (k=0; k < READ_PORT_COUNT; k=k+1) begin: per_read_port
            if (read_enable[k] == 1'b1) begin
                read_data [WORD_WIDTH*k +: WORD_WIDTH] <= ram [read_address [ADDR_WIDTH*k +: ADDR_WIDTH]];
            end
        end
        for (l=0; l < READ_PORT_COUNT; l=l+1) begin: per_read_reset
            if (clear == 1'b1) begin
                read_data [WORD_WIDTH*l +: WORD_WIDTH] <= INIT_VALUE;
            end
        end
    end

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
    integer m;
        if (USE_INIT_FILE == 0) begin
            initial begin
                for (m=0; m < DEPTH; m=m+1) begin: per_ram_init
                    ram[m] = INIT_VALUE;
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

