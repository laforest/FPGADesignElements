
//# Gray to Binary (Reflected Binary)

// *(This code was contributed by Jeff Cassidy at Isophase Computing
// (<jeff@isophase-computing.ca>, <https://github.com/isophase>), with edits
// by myself.)*

// Converts a Reflected Binary [Gray
// Code](https://en.wikipedia.org/wiki/Gray_code) to the corresponding
// unsigned binary number. 

// Because of the abundance of binary adder/subtractor logic on an FPGA, if
// you want to do arithmetic with a Gray Code number, you are better off to
// first convert it to binary, do the math, then [convert it back to Gray
// Code](./Binary_to_Gray_Reflected.html).

`default_nettype none

module Gray_to_Binary_Reflected
#(
    parameter WORD_WIDTH = 0
)
(
    input  wire [WORD_WIDTH-1:0] gray_in,
    output reg  [WORD_WIDTH-1:0] binary_out
);

    localparam ZERO = {WORD_WIDTH{1'b0}};

    initial begin
        binary_out = ZERO;
    end

    function [WORD_WIDTH-1:0] gray_to_binary
    (
        input [WORD_WIDTH-1:0] gray
    );
        integer i;
        reg [WORD_WIDTH-1:0] binary;

        binary[WORD_WIDTH-1] = gray[WORD_WIDTH-1];

        for(i=WORD_WIDTH-2; i >= 0; i=i-1) begin
            binary[i] = binary[i+1] ^ gray[i];
        end

        gray_to_binary = binary;
    endfunction

    always@(*) begin
        binary_out = gray_to_binary(gray_in);
    end

endmodule

