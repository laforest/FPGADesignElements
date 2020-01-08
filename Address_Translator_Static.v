
//# Address Translator (Static)

// Translates a *fixed*, arbitrary, unaligned range of N address bits into an
// aligned range (starting at zero, up to N-1) so the address can be used to
// sequentially index into other addressed components (multiplexers, address
// decoders, RAMs, etc...).  **Consumes no hardware.**

// When memory-mapping a small memory or a number of control registers to
// a base address that isn't a power-of-2, the least significant bits (LSBs)
// will not address the mapped entries in order. This addressing offset
// scrambles the order of the control registers and of the memory locations so
// that the mapped order no longer matches the internal order of the actual
// hardware, which makes debugging harder.

// If the address range does not start at a power-of-2 boundary, and might not
// span a power-of-2 sized block, the LSBs might not necessarily be
// consecutive, exhaustive, and starting at zero: their order can be rotated
// by the offset to the nearest power-of-2 boundary. 

// However, we can construct a translation table that can optimize down to
// mere rewiring of inputs or internal LUT logic, introducing no timing or
// area overhead.  We implement the table as a small read-only memory which
// translates the raw LSBs into consecutive LSBs to directly address the
// memory or control registers. A separate Address Decoder signals when the
// translation is valid.

// For example, take 4 locations, addressed 0 to 3, but mapped at addresses
// 7 to 10. We want address 7 to access the zeroth location, and so on. The
// address bits must be translated as follows:

//<pre>
//01<b>11</b> --> 00
//10<b>00</b> --> 01
//10<b>01</b> --> 02
//10<b>10</b> --> 03
//</pre>

// You can see the raw two LSBs are in the sequence 3,0,1,2, which we must map
// to 0,1,2,3. We can pre-fill a table with the right values to do that, where
// address 3 will contain value 0, address 0 will contain value 1, etc...

// Typically, you'll need this Address Translator alongside an Address Decoder
// module which decodes a *fixed* address range: either
// [Static](./Address_Decoder_Static.html), or
// [Behavioural](./Address_Decoder_Behavioural.html) or
// [Arithmetic](./Address_Decoder_Arithmetic.html) with constant base and
// bound addresses.

`default_nettype none

module Address_Translator_Static
#(
    parameter       ADDR_COUNT          = 10,
    parameter       ADDR_BASE           = 1034,
    parameter       ADDR_WIDTH          = 4, // Must be at least 1
    parameter       REGISTERED          = 1
)
(
    // Register signals are only used if REGISTERED is 1
    // verilator lint_off UNUSED
    input   wire                        clock,
    input   wire                        clock_enable,
    input   wire                        areset,
    input   wire                        clear,
    // verilator lint_on  UNUSED
    input   wire    [ADDR_WIDTH-1:0]    input_addr,
    output  reg     [ADDR_WIDTH-1:0]    output_addr
);

    localparam ADDR_ZERO = {ADDR_WIDTH{1'b0}};

// **DO NOT MOVE THE FOLLOWING CODE BLOCK!**

// Doing the obvious thing of placing a register at the module output prevents
// the CAD tool from reducing the translation table to simple LUT
// configuration change or input rewiring, and creates a small RAM, which
// works too slowly.  It appears the translation table trick only works when
// outputting straight into logic. Hence, we internally register this module
// *before the translation table* rather than let the user place a register
// after the module output.

    generate
        if (REGISTERED == 0) begin

            reg [ADDR_WIDTH-1:0] internal_addr = ADDR_ZERO;

            always @(*) begin
                internal_addr = input_addr;
            end

        end
        else 
        if (REGISTERED == 1) begin

            wire [ADDR_WIDTH-1:0] internal_addr;

            Register
            #(
                .WORD_WIDTH     (ADDR_WIDTH),
                .RESET_VALUE    (ADDR_ZERO)
            )
            address_translator_reg
            (
                .clock          (clock),
                .clock_enable   (clock_enable),
                .areset         (areset),
                .clear          (clear),
                .data_in        (input_addr),
                .data_out       (internal_addr)
            );
        end
    endgenerate

// Let's create the translation table and specify its implementation as LUT
// logic, otherwise it might end up as a Block RAM at random, and then the
// logic cannot get optimized away.

    localparam ADDR_DEPTH = 2**ADDR_WIDTH;

    (* ramstyle = "logic" *)        // Quartus
    (* ram_style = "distributed" *) // Vivado
    reg [ADDR_WIDTH-1:0] translation_table [ADDR_DEPTH-1:0];

// Now lets construct the translation table entry index **j**. Since **j** is
// used in multiples different ways, as an array index, as a bit vector, and
// as an integer, we need some Verilog workarounds to avoid raising width
// mismatch warnings.

// When initializing **j**, we must zero-pad the narrow address up to the
// width of a Verilog integer, else the width mismatch raises warnings at its
// assigment. If we don't zero-pad, then the later arithmetic on **j** will
// raise warnings because we aren't using full integers.

// We also need a simple loop counter **i** to iterate over the number of
// addresses to translate.

    integer i;
    integer j;
    localparam                  INTEGER_WIDTH   = 32;
    localparam                  PADSIZE         = INTEGER_WIDTH - ADDR_WIDTH;
    localparam [PADSIZE-1:0]    J_PADDING       = {PADSIZE{1'b0}};

// In the case where we are translating fewer addresses than are contained by
// the address range (ADDR_COUNT < ADDR_DEPTH), make sure all translation
// table entries are initialized.

// This also happens when the translation table only contains a single entry:
// ADDR_WIDTH is artificially kept at 1 instead of 0 by the enclosing module,
// else the vector widths all become [-1:0], which is invalid.  In the case of
// a single entry, the LSB (**j**) will be either 1 or 0, but always
// translates to 0, thus this constant logic will optimize away.

// We then populate the translation table by calculating each possible input
// address in order, then using its LSBs as an index to store the corresponding
// translated address, which is a simple count starting at 0. Unused entries
// stay at zero, and are filtered out by an Address Decoder anyway.

    initial begin
        for(i = 0; i < ADDR_DEPTH; i = i + 1) begin
            translation_table[i] = ADDR_ZERO;
        end

        j = {J_PADDING, ADDR_BASE[ADDR_WIDTH-1:0]};
        for(i = 0; i < ADDR_COUNT; i = i + 1) begin
            translation_table[j] = i[ADDR_WIDTH-1:0];
            j = (j + 1) % ADDR_DEPTH; // Force wrap-around
        end
    end

// Finally, translate the address using our populated translation table. This
// combinational logic should optimize away as LUT input rewiring or truth
// table re-ordering.

    always @(*) begin
        output_addr = translation_table[internal_addr];
    end

endmodule

