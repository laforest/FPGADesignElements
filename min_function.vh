
//# Min of two signed integers

// Takes two signed integers and returns the *least* positive of the two, or
// `in_A` if equal. For example:

// * min(5,5) returns 5
// * min(5,6) returns 5
// * min(6,5) returns 5
// * min(-6,5) returns -6
// * min(-6,-7) returns -7

// Bring in the function at the start of the body of your module like so:

//    `include "min_function.vh"

// Pass the function a value which, at elaboration time, is either a constant
// or an expression which evaluates to a constant. Then use that value as an
// integer for a localparam, genvar, etc...

// This function is handy when you have words of different parameterized widths
// and you want to scale then all to the width of the smallest word (see: [Width
// Adjuster](./Width_Adjuster.html)).

// Since this is an included file, it must be idempotent. (defined only once globally)

`ifndef MIN_FUNCTION
`define MIN_FUNCTION

function integer min;
    input integer in_A;
    input integer in_B;
    begin
        if (in_A <= in_B) begin
            min = in_A;
        end else begin
            min = in_B;
        end
    end
endfunction

`endif

