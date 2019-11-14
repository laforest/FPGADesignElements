
//# Address Decoder (Arithmetic)

// A programmable address decoder. Works for any address range at any starting
// point, *and the base and bound addresses can be changed at runtime*.  We do
// this with two parallel subtractions [to calculate lesser/greater/equal
// predicates](./Arithmetic_Predicates_Binary.html) to check if the input
// address lies between the base and bound addresses, inclusively.

// This decoder scales to larger address ranges (20 bits or more) without
// hitting any Verilog implementation vector width limits or requiring long
// optimization of enormous netlists, as with the [static Address
// Decoder](./Address_Decoder_Static.html).

// For very small address ranges, this decoder will be larger (2 subtractors
// instead of a few LUTs). For very large address ranges (e.g. 32 bits or
// more), the speed of the arithmetic operations will become a limit, *but it
// is unclear if this will be slower than the log<sub>2</sub>(ADDR_WIDTH) deep
// tree of LUT logic* obtainable from a Behavioural Address Decoder.

// The base, bound, and input addresses all use the same width, which avoids
// the need for selecting parts of vectors and makes the enclosing code
// cleaner and more general.

// **Use this implementation if you must use arithmetic circuitry.**
// Otherwise, I recommend using the [Behavioural Address
// Decoder](./Address_Decoder_Behavioural.html).

`default_nettype none

module Address_Decoder_Arithmetic
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

    wire base_or_higher;
    wire bound_or_lower;

    Arithmetic_Predicates_Binary
    #(
        .WORD_WIDTH         (ADDR_WIDTH)
    )
    lower_bound
    (
        .A                  (addr),
        .B                  (base_addr),

        // verilator lint_off PINCONNECTEMPTY
        .A_eq_B             (),

        .A_lt_B_unsigned    (),
        .A_lte_B_unsigned   (),
        .A_gt_B_unsigned    (),
        .A_gte_B_unsigned   (base_or_higher),

        .A_lt_B_signed      (),
        .A_lte_B_signed     (),
        .A_gt_B_signed      (),
        .A_gte_B_signed     ()
        // verilator lint_on PINCONNECTEMPTY
    );

    Arithmetic_Predicates_Binary
    #(
        .WORD_WIDTH         (ADDR_WIDTH)
    )
    upper_bound
    (
        .A                  (addr),
        .B                  (bound_addr),

        // verilator lint_off PINCONNECTEMPTY
        .A_eq_B             (),

        .A_lt_B_unsigned    (),
        .A_lte_B_unsigned   (bound_or_lower),
        .A_gt_B_unsigned    (),
        .A_gte_B_unsigned   (),

        .A_lt_B_signed      (),
        .A_lte_B_signed     (),
        .A_gt_B_signed      (),
        .A_gte_B_signed     ()
        // verilator lint_on PINCONNECTEMPTY
    );

    always @(*) begin
        hit  = (base_or_higher == 1'b1) && (bound_or_lower == 1'b1);
    end

endmodule

