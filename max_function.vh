
//# Max of two signed integers

// Takes two signed integers and returns the most positive of the two, or
// `in_A` if equal. For example:

// * max(5,5) returns 5
// * max(5,6) returns 6
// * max(6,5) returns 6
// * max(-6,5) returns 5
// * max(-6,-7) returns -6

// Bring in the function at the start of the body of your module like so:

//    `include "max_function.vh"

// Pass the function a value which, at elaboration time, is either a constant
// or an expression which evaluates to a constant. Then use that value as an
// integer for a localparam, genvar, etc...

// This function is handy when you have words of different parameterized widths
// and you want to scale then all to the width of the largest word (see: [Width
// Adjuster](./Width_Adjuster.html)).

function integer max;
    input integer in_A;
    input integer in_B;
    begin
        if (in_A >= in_B) begin
            max = in_A;
        end else begin
            max = in_B;
        end
    end
endfunction

