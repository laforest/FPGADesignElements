
//# Ceiling of log<sub>2</sub>(N) function

// Taken from the Verilog-2001 Language Reference Manual (LRM) standard example
// since $clog2() doesn't exist prior to Verilog-2005 (and thus,
// SystemVerilog).

// This returns the necessary number of bits to index N items with a binary
// integer. For example:

// * clog2(15) returns 4
// * clog2(16) returns 4
// * clog2(17) returns 5
// * etc...

// Bring in the function at the start of the body of your module like so:

//    `include "clog2_function.vh"

// Pass the function a value which, at elaboration time, is either a constant
// or an expression which evaluates to a constant. Then use that value as an
// integer for a localparam, genvar, etc...

// You don't need this function often, but it's very handy when a module
// receives some item count as a parameter, and you need to create an internal
// register to hold an index to those items (e.g.: a binary counter).

function integer clog2;
    input integer value;
    begin
        value = value - 1;
        for (clog2 = 0; value > 0; clog2 = clog2 + 1) begin
            value = value >> 1;
        end
    end
endfunction

