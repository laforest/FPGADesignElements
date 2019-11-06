
//# A Simple Binary Integer Adder/Subtractor

// This is a basic integer adder/subtractor, with carry-in and carry-out.
// The operation is selected with `add_sub`: setting it to 0 for an ad (A+B), and
// to 1 for a subtract (A-B). This assignment matches the convention of sign bits,
// which may end up being convenient.

// On FPGAs, you are much better off letting the CAD tool infer the
// add/subtract circuitry from the `+` or `-` operator itself, rather than
// structurally describing it in logic, as the latter may not get mapped to
// the fast, dedicated ripple-carry hardware. Wrapping all this into a module
// hides the width adjustment necessary to get a warning-free synthesis of
// carry logic.

`default_nettype none

module Adder_Subtractor_Binary
#(
    parameter               WORD_WIDTH          = 0
)
(
    input   wire                                add_sub,    // 0/1 -> A+B/A-B
    input   wire                                carry_in,
    input   wire    signed  [WORD_WIDTH-1:0]    A_in,
    input   wire    signed  [WORD_WIDTH-1:0]    B_in,
    output  reg     signed  [WORD_WIDTH-1:0]    sum_out,
    output  reg                                 carry_out
);

    localparam ZERO = {WORD_WIDTH{1'b0}};

    initial begin
        sum_out     = ZERO;
        carry_out   = 1'b0;
    end

// Extend the `carry_in` to the full word width, so we don't have width
// mismatches nor rely on sign extension, which is full of pitfalls, and would
// trigger useless warnings in the CAD tools.

    reg [WORD_WIDTH-1:0] carry_in_ext = ZERO;

    always @(*) begin
        carry_in_ext = {{WORD_WIDTH-1{1'b0}},carry_in};
    end

// Then perform and select the operation in the usual way. On FPGAs, the CAD
// tool will feed `carry_in` to the carry-in pin of the dedicated adder
// circuitry.

    always @(*) begin
        {carry_out, sum_out} = (add_sub == 1'b0) ? A_in + B_in + carry_in_ext : A_in - B_in - carry_in_ext;
    end

endmodule

