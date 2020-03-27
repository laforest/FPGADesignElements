
//# A Priority Encoder

// Takes in a bitmask of multiple requests and returns the zero-based index of
// the set request bit with the highest priority. The least-significant bit
// has highest priority. If no request bits are set, the output is zero, but
// signalled as invalid.  This Priority Encoder is very closely related to the
// [Number of Trailing Zeros](./Number_of_Trailing_Zeros.html) module. 

// For example:

// * 11111 --> 00000 (0)
// * 00010 --> 00001 (1)
// * 01100 --> 00010 (2)
// * 11000 --> 00011 (3)
// * 10000 --> 00011 (4)
// * 00000 --> 00000 (0, invalid)

// The Priority Encoder translates bitmasks to integers, and so can be
// generally used to convert separate physical events into a number for later
// processing or to index into a table, while filtering out multiple
// simultaneous events into only one.

`default_nettype none

module Priority_Encoder
#(
    parameter WORD_WIDTH = 0
)
(
    input   wire    [WORD_WIDTH-1:0]    word_in,
    output  wire    [WORD_WIDTH-1:0]    word_out,
    output  reg                         word_out_valid
);

    localparam WORD_ZERO = {WORD_WIDTH{1'b0}};

    initial begin
        word_out_valid  = 1'b0;
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
// zero-based index, which is also the encoded priority.

    wire logarithm_undefined;

    Logarithm_of_Powers_of_Two
    #(
        .WORD_WIDTH             (WORD_WIDTH)
    )
    calc_bit_index
    (
        .one_hot_in             (lsb_1),
        .logarithm_out          (word_out),
        .logarithm_undefined    (logarithm_undefined)
    );

// However, there is a corner case: if the input word is all zero then the
// logarithm output is undefined, and so the output number is zero as if the
// zeroth bit was set, but invalid.

    always @(*) begin
        word_out_valid = (logarithm_undefined == 1'b0);
    end

endmodule

