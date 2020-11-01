
//# Adjust a number to the next higher given multiple, if not already an exact multiple.

// Given a number (bit width, word count, etc...) and a multiple, returns the
// number of bits/words/etc... padded upwards to the next multiple, if
// necessary.

// Pass the function values which, at elaboration time, are either constants
// or expressions which evaluate to a constant. Then use the return value as an
// integer for a localparam, genvar, etc...

function integer adjust_to_multiple;
    input integer count;
    input integer multiple;
          integer remainder;
          integer pad;
    begin
        remainder = count % multiple;
        pad = (remainder > 0) ? multiple - remainder : 0;
        adjust_to_multiple = count + pad;
    end
endfunction

