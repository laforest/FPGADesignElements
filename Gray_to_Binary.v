// Converts from Gray code (Reflected Binary Code) to an unsigned binary number
// see en.wikipedia.org/wiki/Gray_code
//
// The key properties of an N-bit Gray code sequence s_N[k] are:
//      P1: it is cyclic with length 2^N
//      P2: each successive code differs in exactly 1 bit
//          ie hamming_distance( s[k], s[k+1 mod 2**N] ) == 1 for k=0..2**N-1
//
// RBC starts from a simple 1-bit sequence 0,1 and can be constructed
// recursively for larger bit widths N. The sequence for N bits s_N is
// the concatenation of:
//      1. The sequence s_(N-1) with 0 prepended to each element, and
//      2. s_(N-1) reversed with 1 prepended to each element
//
// N=1 bit:     0,   1
// N=2 bits:    00,  01, 11, 10 
// N=3 bits:    000, 001, 011, 010, 110, 111, 101, 100
// ...
//
// Informal proof of P1/P2 for RBCs:
// 1. Assume properties hold for s_(N-1)
// 2. Concatenation of two sequences length 2^(N-1) is 2^N -> P1 holds
// 3. Within each of the two sub-lists, prepending the same constant to every
//      element does not invalidate P2
// 4. Where the lists are concatenated in the middle:
//      hamming_distance({0,s_(N-1)[2**(N-1)-1]}, {1,s_(N-1)[2**(N-1)-1]}) == 1
//      because the latter part of each concatenation is the same
// 5. Likewise, where the list cycles back from end to start:
//      hamming_distance({0,s_(N-1)[0]},{1,s_(N-1)[0]}) == 1
// 6. Properties valid for s_(N-1) --> properties valid for S_N
// 7. Properties valid for s_1 = {0,1} --> valid for positive integers by induction
//
//
// Binary (b) -> Gray (g)
//
// g[N-1] = b[N-1]
// g[i]   = b[i]   ^ b[i-1],    i = N-2..0
//
//
// Gray (g) -> binary (b) [separate module, Gray_to_Binary.v]
//
// b[N-1] = g[N-1]
// b[i]   = cumulative_xor ( g[N-1], g[N-2], .. g[i] )

`default_nettype none

module Gray_to_Binary
#(
    parameter integer WIDTH=1
)
(
    input  wire [WIDTH-1:0] gray_in,
    output reg  [WIDTH-1:0] binary_out
);

    localparam ZERO = {WIDTH{1'b0}};

    function automatic [WIDTH-1:0] gray_to_binary(input [WIDTH-1:0] gray);
        reg [WIDTH-1:0] binary;
        integer i;
        binary[WIDTH-1] = gray[WIDTH-1];
        for(i=WIDTH-2;i>=0;i=i-1) begin
            binary[i] = binary[i+1] ^ gray[i];
        end
        gray_to_binary = binary;
    endfunction

    initial begin
        binary_out = ZERO;
    end

    always@(*) begin
        binary_out = gray_to_binary(gray_in);
    end

endmodule
