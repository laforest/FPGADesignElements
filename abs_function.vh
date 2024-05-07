
//# Absolute Value Function

// Takes in a 32-bit signed integer and returns its absolute value.
// *This is not meant for synthesis!*

// Bring in the function at the start of the body of your module like so:

//    `include "abs_function.vh"

// Pass the function values which, at elaboration time, are either constant or
// expressions which evaluates to constants. Then use the output value as an
// integer for a localparam, genvar, etc...

// Since this is an included file, it must be idempotent. (defined only once globally)

`ifndef ABS_FUNCTION
`define ABS_FUNCTION

function integer abs;
    input integer value;
    begin
        abs = (value < 0) ? -value : value;
    end
endfunction

`endif

