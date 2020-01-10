
//# Address Translator (Static)

// Translates a *fixed*, arbitrary, unaligned range of N locations into an
// aligned range (starting at zero, up to N-1) so the translated address can
// be used to sequentially index into other addressed components
// (multiplexers, address decoders, RAMs, etc...).

// When memory-mapping a small memory or a number of control registers to
// a base address that isn't a power-of-2, the Least Significant Bits (LSBs)
// which vary over the address range will not address the mapped entries in
// order. This addressing offset scrambles the order of the control registers
// and of the memory locations so that the mapped order no longer matches the
// physical order of the actual hardware, which makes design and debugging
// harder.

// If the address range does not start at a power-of-2 boundary, the LSBs will
// not count in strictly increasing order and will not start at zero: the
// order of the numbers the LSBs represent is rotated by the offset to the
// nearest power-of-2 boundary. Also, if the address range does not span
// a power-of-2 sized block, then not all possible LSB values will be present.

// However, we can describe a translation table as a small asynchronous
// read-only memory which translates only the raw LSBs into consecutive LSBs
// to then directly address the memory or control registers. A separate
// [Address Decoder](./Address_Decoder_Behavioural.html) signals when the
// translation is valid.

// For example, take 4 locations at addresses 7 to 10, which we would like to
// map to a range of 0 to 3. We want address 7 to access the zeroth location,
// and so on. To map 4 locations, the address' two LSBs must be translated as
// follows:

//<pre>
//01<b>11</b> (7)  --> 01<b>00</b> (4)
//10<b>00</b> (8)  --> 10<b>01</b> (5)
//10<b>01</b> (9)  --> 10<b>10</b> (6)
//10<b>10</b> (10) --> 10<b>11</b> (7)
//</pre>

// You can see the raw two LSBs are in the sequence 3,0,1,2, which we must map
// to 0,1,2,3. We can pre-fill a table with the right values to do that, where
// address 3 will contain value 0, address 0 will contain value 1, etc...
// Translating the LSBs like so re-aligns the addresses to the nearest
// power-of-2 boundary, leaving the LSBs in the order we need.

// Typically, you'll need this Address Translator alongside an Address Decoder
// module which decodes a *fixed* address range: either
// [Static](./Address_Decoder_Static.html), or
// [Behavioural](./Address_Decoder_Behavioural.html) or
// [Arithmetic](./Address_Decoder_Arithmetic.html) with constant base and
// bound addresses.

// Since we only translate the LSBs, the higher address bits are unused here,
// and would trigger CAD tool warnings about module inputs not driving
// anything.  Thus, we don't select the LSBs from the whole address here, and
// it is up to the enclosing module to feed the Address Translator only the
// necessary LSBs, which is fine since the enclosing module must already know
// the number of LSBs to translate. The output is the translated LSBs in
// consecutive order.

`default_nettype none

module Address_Translator_Static
#(
    parameter       INPUT_ADDR_BASE     = 1037,
    parameter       OUTPUT_ADDR_WIDTH   = 4
)
(
    input   wire    [OUTPUT_ADDR_WIDTH-1:0] input_addr,
    output  reg     [OUTPUT_ADDR_WIDTH-1:0] output_addr
);

// Let's create the translation table and specify its implementation as LUT
// logic, otherwise it might end up as a Block RAM or asynchronous LUT RAM at
// random, and then the table cannot get optimized into other logic, and will
// likely be too slow. We make the table deep enough to hold all possible LSB
// values, which enables better logic optimization (no special cases for
// unused addresses).

    localparam OUTPUT_ADDR_DEPTH = 2**OUTPUT_ADDR_WIDTH;

    (* ramstyle = "logic" *)        // Quartus
    (* ram_style = "distributed" *) // Vivado
    reg [OUTPUT_ADDR_WIDTH-1:0] translation_table [OUTPUT_ADDR_DEPTH-1:0];

// Now lets construct the translation table entry index **j**. When
// initializing **j**, we must zero-pad the narrow input address up to the
// width of a Verilog integer, else the width mismatch raises warnings at its
// assigment. 

// We also need a simple loop counter **i** to iterate over the number of
// addresses to translate, which is the entire range described by the LSBs.

    integer i;
    integer j;
    localparam INTEGER_WIDTH    = 32;
    localparam PADSIZE          = INTEGER_WIDTH - OUTPUT_ADDR_WIDTH;
    localparam PADDING          = {PADSIZE{1'b0}};

// We then initialize **j** by slicing out the LSBs from the integer base
// address, and then padding it back to an integer. We then store the
// (strictly incrementing) corresponding LSBs from the **i** counter into each
// translation table entry indexed by **j**, wrapping around to the start of
// the table if necessary.

    initial begin
        j = {PADDING, INPUT_ADDR_BASE[OUTPUT_ADDR_WIDTH-1:0]};
        for(i = 0; i < OUTPUT_ADDR_DEPTH; i = i + 1) begin
            translation_table[j] = i[OUTPUT_ADDR_WIDTH-1:0];
            j = (j + 1) % OUTPUT_ADDR_DEPTH;
        end
    end

// Finally, after all these details, the translation itself is trivial.

    always @(*) begin
        output_addr = translation_table[input_addr];
    end

endmodule

