
//# Binary Integer Adder/Subtractor

// A signed binary integer adder/subtractor, with `carry_in`, `carry_out`,
// `overflow`, and all the intermediate `carries` into each bit position (see
// [Carry-In Calculator](./CarryIn_Binary.html) for their uses).

// Addition/subtraction is selected with `add_sub`: 0 for an add (`A+B`), and
// 1 for a subtract (`A-B`). This assignment conveniently matches the
// convention of sign bits. Note that the `overflow` bit is only meaningful
// for signed numbers. For unsigned numbers, use `carry_out` instead.

// On FPGAs, you are much better off letting the CAD tool infer the
// add/subtract circuitry from the `+` or `-` operator itself, rather than
// structurally describing it in logic, as the latter may not get mapped to
// the fast, dedicated ripple-carry hardware. Wrapping all this into a module
// hides the width adjustment necessary to get a warning-free synthesis of
// carry logic and correct `carry_out` calculation.

// Because we handle the carry bits ourselves, we don't depend on the tricky
// Verilog behaviour where all terms of an expression must be declared signed
// else the expression is silently evaluated as unsigned!

`default_nettype none

module Adder_Subtractor_Binary
#(
    parameter       WORD_WIDTH = 8
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

    initial begin
        sum         = ZERO;
        carry_out   = 1'b0;
        overflow    = 1'b0;
    end

// Extend the `carry_in` to the *unsigned* extended word width, so we don't
// have width mismatches nor rely on sign extension, which is full of
// pitfalls, and would trigger useless warnings in the CAD tools.

    wire [WORD_WIDTH-1:0] carry_in_extended;

    Width_Adjuster
    #(
        .WORD_WIDTH_IN  (1),
        .SIGNED         (0),
        .WORD_WIDTH_OUT (WORD_WIDTH)
    )
    extend_carry_in
    (
        .original_input     (carry_in),
        .adjusted_output    (carry_in_extended)
    );

// Generate the 2's-complement negations of `B` and `carry_in_extended`. We do
// this separately to not get bitten by the implicit Verilog width extension
// of each term in an addition with a `carry_out`, which would cause an
// incorrect `carry_out` when subtracting.

    reg [WORD_WIDTH-1:0] B_in_negated               = ZERO;
    reg [WORD_WIDTH-1:0] carry_in_extended_negated  = ZERO;

    always @(*) begin
        B_in_negated                = -B_in;
        carry_in_extended_negated   = -carry_in_extended;
    end

// Then, select the addition terms, depending on the `add_sub` operation.

    reg [WORD_WIDTH-1:0] B_selected         = ZERO;
    reg [WORD_WIDTH-1:0] carry_in_selected  = ZERO;

    always @(*) begin
        B_selected          = (add_sub == 1'b0) ? B_in              : B_in_negated;
        carry_in_selected   = (add_sub == 1'b0) ? carry_in_extended : carry_in_extended_negated;
    end

// And add as usual. Since the left-hand side is one bit wider to hold
// `carry_out`, all other terms are extended to that width (see IEEE
// 1364-2001, Section 4.4, "Expression bit lengths"), and if we had a negation
// here (e.g.  `A - B - carry_in_extended`), then any zero term (such as the
// often zero `carry_in`) would incorrectly generate a set carry bit from its
// own 2's-complement negation!

    always @(*) begin
        {carry_out, sum_out} = A_in + B_selected + carry_in;
    end

// Finally, recover the carry_in of each bit.

    CarryIn_Binary
    #(
        .WORD_WIDTH (WORD_WIDTH)
    )
    per_bit
    (
        .A          (A_in),
        .B          (B_selected),
        .sum        (sum_out),
        .carryin    (carries_out)
    );

// And compute the overflow

    always @(*) begin
        overflow_out = (carry_out != carries_out [WORD_WIDTH-1]);
    end

endmodule

