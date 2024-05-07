
//# Least Common Multiple (LCM) Function

// Takes in two 32-bit integers and uses the GCD-based algorithm to calculate
// their Least Common Multiple (LCM).  *This is not meant for synthesis!*

// Reference: [Wikipedia: Least Common Multiple](https://en.wikipedia.org/wiki/Least_common_multiple)

// Bring in the function at the start of the body of your module like so:

//    `include "lcm_function.vh"

// Pass the function values which, at elaboration time, are either constant or
// expressions which evaluates to constants. Then use the output value as an
// integer for a localparam, genvar, etc...

// The formula is decomposed this way so the division always returns an
// integer, and so we can't end up with intermediate values that don't fit in an
// integer.

// Since this is an included file, it must be idempotent. (defined only once globally)

`ifndef LCM_FUNCTION
`define LCM_FUNCTION

`include "gcd_function.vh"
`include "abs_function.vh"

function integer lcm;
    input integer A;
    input integer B;
    begin
        lcm = abs(A) * (abs(B) / gcd(A,B));
    end
endfunction

`endif

