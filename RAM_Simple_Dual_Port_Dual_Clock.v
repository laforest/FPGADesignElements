
//# Simple Dual-Ported RAM (Dual Clock)

// Defines a memory, of various implementation, with one write port and one
// read port (1W1R), separately addressed, *each with its own, asynchronous
// clock.*  Common data width on both ports. Since the clocks are
// asynchronous, there can be no write-forwarding during coincident reads and
// writes.

// There is no synchronous clear on the read output: In Quartus at least, any
// register driving it cannot be retimed, and it may not be as portable.
// Instead, use separate logic (e.g.: an [Annuller](./Annuller.html)) to
// zero-out the read output down the line.

// *This module is a variation on the single-clocked [Simple Dual Port
// RAM](./RAM_Simple_Dual_Port.html).*

`default_nettype none

module RAM_Simple_Dual_Port_Dual_Clock
#(
    parameter                       WORD_WIDTH          = 0,
    parameter                       ADDR_WIDTH          = 0,
    parameter                       DEPTH               = 0,
    parameter                       RAMSTYLE            = "",
    parameter                       USE_INIT_FILE       = 0,
    parameter                       INIT_FILE           = "",
    parameter   [WORD_WIDTH-1:0]    INIT_VALUE          = 0
)
(
    input  wire                         write_clock,
    input  wire                         wren,
    input  wire     [ADDR_WIDTH-1:0]    write_addr,
    input  wire     [WORD_WIDTH-1:0]    write_data,

    input  wire                         read_clock,
    input  wire                         rden,
    input  wire     [ADDR_WIDTH-1:0]    read_addr, 
    output reg      [WORD_WIDTH-1:0]    read_data
);

    initial begin
        read_data = {WORD_WIDTH{1'b0}};
    end

//## RAM Memory

// Set the ram style to control implementation.
// See your CAD tool documentation for available options.

// For Quartus, to remove inference of write-forwarding, at the price of
// indeterminate behaviour on coincident read/writes, use "no_rw_check" as
// part of the RAMSTYLE (e.g.: "M10K, no_rw_check").  If that fails, add this
// setting to your Quartus project: `set_global_assignment -name
// ADD_PASS_THROUGH_LOGIC_TO_INFERRED_RAMS OFF` to disable creation of
// write-forwarding logic, as Quartus ignores the "no_rw_check" RAMSTYLE for
// M10K BRAMs.

    (* ramstyle  = RAMSTYLE *) // Quartus
    (* ram_style = RAMSTYLE *) // Vivado

// Vivado uses a different mechanism to control write-forwarding: we must set
// RW_ADDR_COLLISION to "no to prevent the inference of write forwarding
// logic, which is meaningless when the read and write clocks are
// asynchronous.

    (* rw_addr_collision = "no" *) // Vivado

// This is the RAM array proper. It is initialized later.

    reg [WORD_WIDTH-1:0] ram [DEPTH-1:0];

//## Read and Write Ports

// The read and write ports operate each on their own clocks. In the limit
// case of having synchronous clocks and coincident reads and writes, there
// will be no write-forwarding: the read port will return the data currently
// in the RAM, not the value of the read.

    always @(posedge write_clock) begin
        if(wren == 1'b1) begin
            ram[write_addr] <= write_data;
        end
    end

    always @(posedge read_clock) begin
        if(rden == 1'b1) begin
            read_data <= ram[read_addr];
        end
    end

//## Memory Initialization

// If you are not using an init file, the following code will set all memory
// locations to INIT_VALUE. The CAD tool should generate a memory
// initialization file from that.  This is useful to cleanly implement small
// collections of registers (e.g.: via RAMSTYLE = "logic" on Quartus), without
// having to deal with an init file.  Your CAD tool may complain about too
// many for-loop iterations if your memory is very deep. Adjust the tool
// settings to allow more loop iterations.

// At a minimum, the initialization file format is one value per line, one for
// each memory word from 0 to DEPTH-1, in bare hexadecimal (e.g.: 0012 to init
// a 16-bit memory word with 16'h12). Note that if your WORD_WIDTH isn't
// a multiple of 4, the CAD tool may complain about the width mismatch.
// You can base yourself on this Python [memory initialization file
// generator](./RAM_generate_empty_init_file.py).

    generate
        if (USE_INIT_FILE == 0) begin
            integer i;
            initial begin
                for (i = 0; i < DEPTH; i = i + 1) begin
                    ram[i] = INIT_VALUE;
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

