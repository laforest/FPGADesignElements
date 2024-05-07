
//# Word count needed to pack/unpack a bit vector

// Given the width of a bit vector, and the width of a word, returns the count
// of words needed to contain the bit vector, even if the last word will be
// partially full. You must compute any pad bits externally using
// [word_pad](./word_pad_function.html).

// Pass the function values which, at elaboration time, are either constants
// or expressions which evaluate to a constant. Then use the return value as an
// integer for a localparam, genvar, etc...

// Since this is an included file, it must be idempotent. (defined only once globally)

`ifndef WORDCOUNT_FUNCTION
`define WORDCOUNT_FUNCTION

function integer word_count;
    input integer bit_vector_width;
    input integer word_width;
          integer word_count_raw;
    begin
        word_count_raw = bit_vector_width / word_width;
        word_count = (bit_vector_width % word_width == 0) ? word_count_raw : word_count_raw + 1;
    end
endfunction

`endif

