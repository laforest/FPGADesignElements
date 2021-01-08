
//# Number of pad bits to fill an incomplete word

// When you want to either group a number of words into a larger bit vector, or
// split a bit vector into a number of smaller words, given the width of a bit
// vector and the width of a word, returns the number of unused bits at the end
// of the last word which must be filled with a pad value (usually zero).
// Handles case where the word width is larger than the bit vector width.

// **NOTE:** since zero-width values cannot exist in Verilog, if no pad bits
// are needed, this function returns `word_width` instead of 0. This case
// cannot normally happen (a pad width is maximum `word_width-1` and minimum
// 0), so you can selectively instantiate the pad by checking if the return
// value of this function is equal to `word_width`, like so:

//<pre>
//localparam PAD_WIDTH = word_pad(bit_vector_width, word_width);
//localparam PAD       = {PAD_WIDTH{1'b0}};
//
//if (PAD_WIDTH != word_width) begin
//    baz = {{PAD, wibble, ....};
//end
//else begin
//    baz = {wibble, ... };
//end
//</pre>

// If you do not need to create a pad, but only need to index to its location,
// you must externally re-convert a `word_width` return value back to 0.

// Pass the function values which, at elaboration time, are either constants
// or expressions which evaluate to a constant. Then use the return value as an
// integer for a localparam, genvar, etc...

function integer word_pad;
    input integer bit_vector_width;
    input integer word_width;
    begin
        word_pad = (bit_vector_width < word_width) ? word_width - bit_vector_width : word_width - (bit_vector_width % word_width);
    end
endfunction

