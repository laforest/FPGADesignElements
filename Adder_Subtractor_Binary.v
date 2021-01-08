
//# Binary Integer Adder/Subtractor

// A signed binary integer adder/subtractor, with `carry_in`, `carry_out`,
// `overflow`, and all the intermediate `carries` into each bit position (see
// [Carry-In Calculator](./CarryIn_Binary.html) for their uses).

// Addition/subtraction is selected with `add_sub`: 0 for an add
// (`A+B+carry_in`), and 1 for a subtract (`A-B-carry_in`). This assignment
// conveniently matches the convention of sign bits. *Note that the `overflow`
// bit is only meaningful for signed numbers. For unsigned numbers, use
// `carry_out` instead.*

// On FPGAs, you are much better off letting the CAD tool infer the
// add/subtract circuitry from the `+` or `-` operator itself, rather than
// structurally describing it in Boolean logic, as the latter may not get
// mapped to the fast, dedicated ripple-carry hardware. Wrapping all this into
// a module hides the width adjustments necessary to get a warning-free
// synthesis of carry logic, and enables correct carry and overflow
// calculations.

// Because we handle the carry bits ourselves and do everything through an
// unsigned addition, we don't depend on the tricky Verilog behaviour where
// all terms of an expression must be declared signed else the expression is
// silently evaluated as unsigned!

`default_nettype none

module Adder_Subtractor_Binary
#(
    parameter       WORD_WIDTH = 0
)
(
    input   wire                        add_sub,    // 0/1 -> A+B/A-B
    input   wire                        carry_in,
    input   wire    [WORD_WIDTH-1:0]    A,
    input   wire    [WORD_WIDTH-1:0]    B,
    output  reg     [WORD_WIDTH-1:0]    sum,
    output  reg                         carry_out,
    output  wire    [WORD_WIDTH-1:0]    carries,
    output  reg                         overflow
);

    localparam ZERO = {WORD_WIDTH{1'b0}};
    localparam ONE  = {{WORD_WIDTH-1{1'b0}},1'b1};

    initial begin
        sum         = ZERO;
        carry_out   = 1'b0;
        overflow    = 1'b0;
    end

// Extend the `carry_in` to the extended word width, as both signed (0 or -1)
// and unsigned (0 or 1) words, so we don't have width mismatches nor rely on
// sign extension, which is full of pitfalls, and would trigger useless
// warnings in the CAD tools.

    wire [WORD_WIDTH-1:0] carry_in_extended_unsigned;
    wire [WORD_WIDTH-1:0] carry_in_extended_signed;

    Width_Adjuster
    #(
        .WORD_WIDTH_IN  (1),
        .SIGNED         (0),
        .WORD_WIDTH_OUT (WORD_WIDTH)
    )
    extend_carry_in_unsigned
    (
        .original_input     (carry_in),
        .adjusted_output    (carry_in_extended_unsigned)
    );

    Width_Adjuster
    #(
        .WORD_WIDTH_IN  (1),
        .SIGNED         (1),
        .WORD_WIDTH_OUT (WORD_WIDTH)
    )
    extend_carry_in_signed
    (
        .original_input     (carry_in),
        .adjusted_output    (carry_in_extended_signed)
    );

// Depending on the value of `add_sub`, generate the bit-negation of `B` and
// the necessary offset for `B`'s 2's-complement arithmetic negation, and
// select the correct `carry_in` value. We do this separately to have the
// negated `B` available later for the calculations of the `carries` and of
// the `overflow`.

    reg [WORD_WIDTH-1:0] B_selected         = ZERO;
    reg [WORD_WIDTH-1:0] negation_offset    = ZERO;
    reg [WORD_WIDTH-1:0] carry_in_selected  = ZERO;

    always @(*) begin
        B_selected          = (add_sub == 1'b0) ? B    : ~B;
        negation_offset     = (add_sub == 1'b0) ? ZERO : ONE;
        carry_in_selected   = (add_sub == 1'b0) ? carry_in_extended_unsigned : carry_in_extended_signed;
    end

// And add as usual, with subtraction expressed as `A+((~B)+1)`, so as to
// generate the correct `carries` for each bit position.

// Since the left-hand side is one bit wider to hold `carry_out`, all other
// terms are implicitly extended to that width (see Verilog LRM, IEEE
// 1364-2001, Section 4.4, "Expression bit lengths").  However, since I avoid
// implicit width extension as a way to reduce warnings and prevent bugs,
// let's prepend a zero to all the unsigned right-hand terms to make all
// widths match and force a simple, unsigned addition.

// We could have done this more concisely by first widening all terms to
// `WORD_WIDTH+1`, then selecting addition/subtraction in one line, but we
// need the possibly negated `B` later for the `carries` and `overflow`
// calculation.

    always @(*) begin
        {carry_out, sum} = {1'b0, A} + {1'b0, B_selected} + {1'b0, negation_offset} + {1'b0, carry_in_selected};
    end

// Finally, recover the carry *into* each bit from the selected addition
// terms.  The first bit of `carries` is the same as `carry_in`.  We must do
// this here rather than in the enclosing module, since if you are
// subtracting, the negated `B` term is not externally available.

    CarryIn_Binary
    #(
        .WORD_WIDTH (WORD_WIDTH)
    )
    per_bit
    (
        .A          (A),
        .B          (B_selected),
        .sum        (sum),
        .carryin    (carries)
    );

// And compute the signed overflow, which happens when the carry into and out
// from the MSB do not agree.

    always @(*) begin
        overflow = (carries [WORD_WIDTH-1] != carry_out);
    end

endmodule

