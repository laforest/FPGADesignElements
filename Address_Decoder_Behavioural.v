
//# Address Decoder (Behavioural)

// A programmable address decoder. Works for any address range at any starting
// point, *and the base and bound addresses can be changed at runtime*.  We
// express this behaviourally with two unsigned integer comparisons to check
// if the address lies between the base and bound of a range, inclusively.

// This decoder scales to larger address ranges (20 bits or more) without
// hitting any Verilog implementation vector width limits or requiring long
// optimization of enormous netlists, as with the [Static Address
// Decoder](./Address_Decoder_Static.html).

// How this circuit synthesizes depends on your CAD tool. In the past, I saw
// this code synthesize to the expected arithmetic comparisons via
// subtraction, but a more recent version of the same CAD tool synthesizes to
// log<sub>2</sub>(ADDR_WIDTH) levels of LUT logic. *But it is unclear if that
// will be faster than arithmetic circuitry.* And of course, if you make the
// base and bound addresses constant, the logic will optimize further towards
// its minimal form.

// The base, bound, and input addresses all use the same width, which avoids
// the need for selecting parts of vectors and makes the enclosing code
// cleaner and more general.

// **This is the implementation I recommend for general use.** You can force
// a non-arithmetic implementation (but with a fixed range) by using the
// Static Address Decoder, or conversely, you can force an arithmetic
// implementation by using the [Arithmetic Address
// Decoder](./Address_Decoder_Arithmetic.html).

`default_nettype none

module Address_Decoder_Behavioural
#(
    parameter       ADDR_WIDTH          = 0
)
(
    input   wire    [ADDR_WIDTH-1:0]    base_addr,
    input   wire    [ADDR_WIDTH-1:0]    bound_addr,
    input   wire    [ADDR_WIDTH-1:0]    addr,
    output  reg                         hit
);

    initial begin
        hit = 1'b0;
    end

    reg base_or_higher = 1'b0;
    reg bound_or_lower = 1'b0;

    always @(*) begin
        base_or_higher = (addr >= base_addr);
        bound_or_lower = (addr <= bound_addr);
        hit            = (base_or_higher == 1'b1) && (bound_or_lower == 1'b1);
    end

endmodule

