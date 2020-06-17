
//# Boolean Bit Reducer

// This module generalizes the usual 2-input Boolean functions to their
// n-input reductions, which are interesting and useful:

// * Trivially calculate *any of these* (OR) or *all of these* (AND) conditions and their negations.
// * Calculate even/odd parity (XOR/XNOR)
// * Selectively invert some of the inputs and you can decode any intermediate condition you care to.

// Beginners can use this module to implement any combinational logic while
// knowing a minimum of Verilog (no always blocks, no blocking/non-blocking
// statements, only wires, etc...).

// Experts generally would not use this module. It's far simpler to [express
// the desired conditions directly](./verilog.html#boolean) in Verilog.
// However, there are a few reasons to use it:

// * It will keep your derived schematics clean of multiple random little gates, and generally preserve the schematic layout.
// * If there is a specific meaning to this reduction, you can name the module descriptively.
// * It will make clear which logic gets moved, in or out of that level of hierarchy, by optimization or retiming post-synthesis.

//## Differences with Verilog Reduction Operators

// The specification of reduction operators in Verilog (2001 or SystemVerilog)
// contains an error which does not perform a true reduction when the Boolean
// operator in the reduction contains an inversion (NOR, NAND, XNOR). Instead,
// the operator will perform a non-inverting reduction (e.g.: XOR), then
// invert the final result. For example, `A = ~^B;` (XNOR reduction) should
// perform the following:

// <pre>(((B[0] ~^ B[1]) ~^ B[2]) ~^ B[3) ... </pre>

// but instead performs the following, which is not always equivalent:

// <pre>~(B[0] ^ B[1] ^ B[2] ^ B[3 ...)</pre>

// To implement the correct logical behaviour, we do the reduction in a loop
// using the alternate implementation described in the [Word
// Reducer](./Word_Reducer.html) module.  The differences were
// [spotted](https://twitter.com/wren6991/status/1259098465835106304) by Luke
// Wren ([@wren6991](https://twitter.com/wren6991)).

//## Errors, Verilog Strings, and Linter Warnings

// There's no clean way to stop the CAD tools if the `OPERATION` parameter is
// missing or incorrect. Here, the logic doesn't get generated, which will
// fail pretty fast...

// The `OPERATION` parameter also reveals how strings are implemented in
// Verilog: just a sequence of 8-bit bytes. Thus, if we give `OPERATION`
// a value of `"OR"` (16 bits), it must first get compared against `"AND"` (24
// bits) and `"NAND"` (32 bits). The Verilator linter throws a width mismatch
// warning at those first two comparisons, of course. Width warnings are
// important to spot bugs, so to keep them relevant we carefully disable width
// checks only during the parameter tests.

`default_nettype none

module Bit_Reducer
#(
    parameter OPERATION     = "",
    parameter INPUT_COUNT   = 0
)
(
    input   wire    [INPUT_COUNT-1:0]   bits_in,
    output  reg                         bit_out
);

    localparam INPUT_ZERO = {INPUT_COUNT{1'b0}};

    initial begin
        bit_out = 1'b0;
    end

// First, initialize the partial reduction storage. Each partial reduction
// must be stored in its own storage, else we describe a broken combinational
// loop.

// To make the code clearer, `partial_reduction` is read and written in
// different `always` blocks, so the linter is confused and sees a potential
// combinational loop, which doesn't exist here because of the non-overlapping
// indices. So we disable that warning here.

    // verilator lint_off UNOPTFLAT
    reg [INPUT_COUNT-1:0] partial_reduction;
    // verilator lint_on  UNOPTFLAT

    integer i;

    initial begin
        for(i=0; i < INPUT_COUNT; i=i+1) begin
            partial_reduction[i] = 1'b0;
        end
    end

// Then prime the partial reductions with the first input, and read out the
// result at the last partial reduction.

    always @(*) begin
        partial_reduction[0]    = bits_in[0];
        bit_out                 = partial_reduction[INPUT_COUNT-1];
    end

// Finally, select the logic to instantiate based on the `OPERATION`
// parameter. Each partial reduction is the combination of the previous
// reduction and the current corresponding input bit.

    generate

        // verilator lint_off WIDTH
        if (OPERATION == "AND") begin
        // verilator lint_on  WIDTH
            always @(*) begin
                for(i=1; i < INPUT_COUNT; i=i+1) begin
                    partial_reduction[i] = partial_reduction[i-1] & bits_in[i];
                end
            end
        end
        else
        // verilator lint_off WIDTH
        if (OPERATION == "NAND") begin
        // verilator lint_on  WIDTH
            always @(*) begin
                for(i=1; i < INPUT_COUNT; i=i+1) begin
                    partial_reduction[i] = ~(partial_reduction[i-1] & bits_in[i]);
                end
            end
        end
        else
        // verilator lint_off WIDTH
        if (OPERATION == "OR") begin
        // verilator lint_on  WIDTH
            always @(*) begin
                for(i=1; i < INPUT_COUNT; i=i+1) begin
                    partial_reduction[i] = partial_reduction[i-1] | bits_in[i];
                end
            end
        end
        else
        // verilator lint_off WIDTH
        if (OPERATION == "NOR") begin
        // verilator lint_on  WIDTH
            always @(*) begin
                for(i=1; i < INPUT_COUNT; i=i+1) begin
                    partial_reduction[i] = ~(partial_reduction[i-1] | bits_in[i]);
                end
            end
        end
        else
        // verilator lint_off WIDTH
        if (OPERATION == "XOR") begin
        // verilator lint_on  WIDTH
            always @(*) begin
                for(i=1; i < INPUT_COUNT; i=i+1) begin
                    partial_reduction[i] = partial_reduction[i-1] ^ bits_in[i];
                end
            end
        end
        else
        // verilator lint_off WIDTH
        if (OPERATION == "XNOR") begin
        // verilator lint_on  WIDTH
            always @(*) begin
                for(i=1; i < INPUT_COUNT; i=i+1) begin
                    partial_reduction[i] = ~(partial_reduction[i-1] ^ bits_in[i]);
                end
            end
        end

    endgenerate
endmodule

