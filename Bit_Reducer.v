
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

// There's no clean way to stop the CAD tools if the `OPERATION` parameter is
// missing or incorrect. Here, the logic doesn't get generated, which will
// fail pretty fast...

// The `OPERATION` parameter also reveals how strings are implemented in
// Verilog: just a sequence of 8-bit bytes. Thus, if we give `OPERATION`
// a value of `"OR"` (16 bits), it must first get compared against `"AND"` (24
// bits) and `"NAND"` (32 bits). The Verilator linter throws a width mismatch
// warning at those first two comaprisons, of course. Width warnings are
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

    initial begin
        bit_out = 1'b0;
    end

    generate

        // verilator lint_off WIDTH
        if (OPERATION == "AND") begin
        // verilator lint_off WIDTH
            always @(*) begin
                bit_out = &bits_in;
            end
        end
        else
        // verilator lint_off WIDTH
        if (OPERATION == "NAND") begin
        // verilator lint_off WIDTH
            always @(*) begin
                bit_out = ~&bits_in;
            end
        end
        else
        // verilator lint_off WIDTH
        if (OPERATION == "OR") begin
        // verilator lint_off WIDTH
            always @(*) begin
                bit_out = |bits_in;
            end
        end
        else
        // verilator lint_off WIDTH
        if (OPERATION == "NOR") begin
        // verilator lint_off WIDTH
            always @(*) begin
                bit_out = ~|bits_in;
            end
        end
        else
        // verilator lint_off WIDTH
        if (OPERATION == "XOR") begin
        // verilator lint_off WIDTH
            always @(*) begin
                bit_out = ^bits_in;
            end
        end
        else
        // verilator lint_off WIDTH
        if (OPERATION == "XNOR") begin
        // verilator lint_off WIDTH
            always @(*) begin
                bit_out = ~^bits_in;
            end
        end

    endgenerate
endmodule

