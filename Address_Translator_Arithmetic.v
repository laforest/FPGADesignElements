
//# Address Translator (Arithmetic)

// *This is the run-time adjustable version of the [Static Address
// Translator](./Address_Translator_Static.html).*

// Translates a *variable*, arbitrary, unaligned range of N locations into an
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

// However, we can add the offset back to translate the raw LSBs into
// consecutive LSBs to then directly address the memory or control registers.
// A separate [Address Decoder](./Address_Decoder_Behavioural.html) signals
// when the translation is valid.

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
// to 0,1,2,3. This means re-aligning the addresses to the nearest power-of-2
// boundary, leaving the LSBs in the order we need, and that's a simple
// subtraction of the value of the initial, untranslated LSBs (3).

// Typically, you'll need this Address Translator alongside an Address Decoder
// module which decodes a *variable* address range: either the
// [Behavioural](./Address_Decoder_Behavioural.html) or
// [Arithmetic](./Address_Decoder_Arithmetic.html) decoders.

// Since we only translate the LSBs, the higher address bits are unused here,
// and would trigger CAD tool warnings about module inputs not driving
// anything.  Thus, we don't select the LSBs from the whole address here, and
// it is up to the enclosing module to feed the Address Translator only the
// necessary LSBs, which is fine since the enclosing module must already know
// the number of LSBs to translate. The output is the translated LSBs in
// consecutive order.

`default_nettype none

module Address_Translator_Arithmetic
#(
    parameter       OUTPUT_ADDR_WIDTH = 0
)
(
    input   wire    [OUTPUT_ADDR_WIDTH-1:0] offset,
    input   wire    [OUTPUT_ADDR_WIDTH-1:0] input_addr,
    output  wire    [OUTPUT_ADDR_WIDTH-1:0] output_addr
);

    Adder_Subtractor_Binary
    #(
        .WORD_WIDTH (OUTPUT_ADDR_WIDTH)
    )
    address_offset
    (
        .add_sub    (1'b1),    // 0/1 -> A+B/A-B
        .carry_in   (1'b0),
        .A          (input_addr),
        .B          (offset),
        .sum        (output_addr),
        // verilator lint_off PINCONNECTEMPTY
        .carry_out  (),
        .carries    (),
        .overflow   ()
        // verilator lint_on  PINCONNECTEMPTY
    );

endmodule

