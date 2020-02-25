
//# Number of Trailing Zeros

// Takes in a binary number and returns an unsigned binary number of the same
// width containing the count of zeros from the least-significant bit up to
// the first 1 bit (trailing zeros), or the width of the word if all-zero. 
// For example:

// * 11111 --> 00000 (0)
// * 00010 --> 00001 (1)
// * 01100 --> 00010 (2)
// * 11000 --> 00011 (3)
// * 10000 --> 00011 (4)
// * 00000 --> 00101 (5)

`default_nettype none

module Number_of_Trailing_Zeros
#(
    parameter WORD_WIDTH = 0
)
(
    input   wire    [WORD_WIDTH-1:0]    word_in,
    output  reg     [WORD_WIDTH-1:0]    word_out
);

    localparam WORD_ZERO = {WORD_WIDTH{1'b0}};

    initial begin
        word_out = WORD_ZERO;
    end

// First, isolate the least-significant 1 bit

    wire [WORD_WIDTH-1:0] lsb_1;

    Bitmask_Isolate_Rightmost_1_Bit
    #(
        .WORD_WIDTH (WORD_WIDTH)
    )
    find_lsb_1
    (
        .word_in    (word_in),
        .word_out   (lsb_1)
    );

// A single bit is a power of two, so take its logarithm, which returns its
// zero-based index, which is also the number of trailing zeros behind it.

    wire [WORD_WIDTH-1:0]   trailing_zero_count_raw;
    wire                    logarithm_undefined;

    Logarithm_of_Powers_of_Two
    #(
        .WORD_WIDTH             (WORD_WIDTH)
    )
    calc_bit_index
    (
        .one_hot_in             (lsb_1),
        .logarithm_out          (trailing_zero_count_raw),
        .logarithm_undefined    (logarithm_undefined)
    );

// However, there is a corner case: if the input word is all zero, then the
// logarithm output is undefined, and the number of trailing zeros is equal
// to WORD_WIDTH, which is a value the logarithm (base 2) can never take.

    always @(*) begin
        word_out = (logarithm_undefined == 1'b1) ? WORD_WIDTH : trailing_zero_count_raw;
    end

endmodule

