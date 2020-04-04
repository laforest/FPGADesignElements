
//# Binary to Gray (Reflected Binary)

// *(This code was contributed by Jeff Cassidy at Isophase Computing
// (<jeff@isophase-computing.ca>, <https://github.com/isophase>), with edits
// by myself.)*

// Converts an unsigned binary number to the corresponding Reflected Binary
// [Gray Code](https://en.wikipedia.org/wiki/Gray_code).

// A Reflected Binary Gray Code starts from a simple 1-bit sequence 0,1 and
// can be constructed recursively for larger bit widths N. The sequence for
// N bits is build as follows:

// * The sequence of N-1 bits with 0 prepended to each element, concatenated with
// * the sequence of N-1 bits *reversed* with 1 prepended to each element

// For example:

// * N=1 bit: 0, 1
// * N=2 bits: 00, 01, 11, 10 
// * N=3 bits: 000, 001, 011, 010, 110, 111, 101, 100

// The resulting Reflected Binary Gray Code has two useful properties:

// * It is cyclic with length 2<sup>N</sup>, so it can represent or index the
// same number of items as a binary coded number of the same length.
// * Each Gray code word differs by exactly 1 bit from the previous and the
// next code in sequence, which makes it behave nicely if a word may be read
// inaccurately from a mechanical indicator or a Clock Domain Crossing.
// Missing the changed bit means you are off by 1 step, not some variable
// number of steps as with a binary code.

// The [reverse function](./Gray_to_Binary_Reflected.html) also exists.

`default_nettype none

module Binary_to_Gray_Reflected
#(
    parameter WORD_WIDTH = 0
)
(
    input  wire [WORD_WIDTH-1:0]  binary_in,
    output reg  [WORD_WIDTH-1:0]  gray_out
);

    localparam ZERO = {WORD_WIDTH{1'b0}};

    initial begin
        gray_out = ZERO;
    end

    function [WORD_WIDTH-1:0] binary_to_gray
    (
        input [WORD_WIDTH-1:0] binary
    );
        integer i;
        reg [WORD_WIDTH-1:0] gray;

        begin
            for(i=0; i < WORD_WIDTH-1; i=i+1) begin
                gray[i] = binary[i] ^ binary[i+1];
            end

            gray[WORD_WIDTH-1] = binary[WORD_WIDTH-1];

            binary_to_gray = gray;
        end
    endfunction
    
    always@(*) begin
        gray_out = binary_to_gray(binary_in);
    end

endmodule
