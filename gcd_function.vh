
//# Greatest Common Divisor (GCD) Function

// Uses Euclid's Algorithm to iteratively find the greatest common divisor of
// two signed integers, A and B, of up to 32 bits.  *This is not mean for
// synthesis!*

// Reference: [Wikipedia: Euclidean Algorithm](https://en.wikipedia.org/wiki/Euclidean_algorithm)

// Bring in the function at the start of the body of your module like so:

//    `include "gcd_function.vh"

// Pass the function values which, at elaboration time, are either constant or
// expressions which evaluates to constants. Then use the output value as an
// integer for a localparam, genvar, etc...

// We use a temp values for calculations since Vivado raises warnings if we
// internally assign a value to a function input port.

// Since this is an included file, it must be idempotent. (defined only once globally)

`ifndef GCD_FUNCTION
`define GCD_FUNCTION

`include "abs_function.vh"

function integer gcd;
    input integer A;
    input integer B;
          integer A_tmp;
          integer B_tmp;
          integer tmp;
    begin
        A_tmp = A;
        B_tmp = B;
        while ( B_tmp != 0) begin
            tmp = B_tmp;
            B_tmp = A_tmp % B_tmp;
            A_tmp = tmp;
        end
        gcd = abs(A_tmp);
    end
endfunction

`endif

