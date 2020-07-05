
//# Bit Voting

// Counts the number of set bits in the input word as a vote, with the
// following possible results:

// * Unanimity of Ones (all bits are set)
// * Unanimity of Zeros (all bits are unset)
// * Majority (low on a tie, high on unanimity of ones)
// * Minority (low on a tie, high on unnanimity of zeros)
// * Tie (only possible for an even number of input bits)

// Each result is valid by itself. There is no need to check multiple outputs
// to decode certain situations. This is why the unanimity output is split
// into two cases, else you would have to look at the majority and minority
// outputs to figure out which kind of unanimity happened.

// Implemented by calculating the population count of the input (number of
// bits set), then comparing this value against the expected number of set
// bits for each voting outcome, with an extra check for tie to remove the
// logic if the number of input bits is not even.

`default_nettype none

module Bit_Voting
#(
    parameter INPUT_COUNT = 0
)
(
    input   wire    [INPUT_COUNT-1:0]   word_in,
    output  reg                         unanimity_ones,
    output  reg                         unanimity_zeros,
    output  reg                         majority,
    output  reg                         minority,
    output  reg                         tie
);

    initial begin
        unanimity_ones  = 1'b0;
        unanimity_zeros = 1'b0;
        majority        = 1'b0;
        minority        = 1'b0;
        tie             = 1'b0;
    end

// Pre-compute the expected count of set bits for each voting outcome. Note
// the corner case of ties: it's always correct when used to compute majority,
// but not to compute a tie when the number of votes is not even, so we must
// also pre-compute if the number of votes is even or not.

// The pre-computed values default to unsigned integers, so we can reliably
// specify the bit width of a pre-computed value to make it match the width of
// later arithmetic comparisons, where signs and width expansion can be
// difficult to get right, and are best avoided if at all possible. If the
// `INPUT_COUNT` is larger than the width of an integer in your Verilog
// implementation (at least 32 bits), using it as the bit width will
// zero-extend the value to that width, else it will truncate it.

    localparam [INPUT_COUNT-1:0] UNANIMITY_ONES   = INPUT_COUNT;
    localparam [INPUT_COUNT-1:0] UNANIMITY_ZEROS  = 0;
    localparam                   COUNT_IS_EVEN    = (INPUT_COUNT % 2) == 0;
    localparam [INPUT_COUNT-1:0] TIE              = INPUT_COUNT / 2;
    localparam [INPUT_COUNT-1:0] MAJORITY         = TIE + 1;
    localparam [INPUT_COUNT-1:0] MINORITY         = INPUT_COUNT - MAJORITY;

// Then count the number of set bits. See the implementation notes in the
// [Population Count](./Population_Count.html) module if you need to
// understand why we have the popcount width be the same as the input width,
// and not the expected log<sub>2</sub>(INPUT_COUNT)+1 bits.

    wire [INPUT_COUNT-1:0] popcount;

    Population_Count
    #(
        .WORD_WIDTH (INPUT_COUNT)
    )
    ones_count
    (
        .word_in    (word_in),
        .count_out  (popcount)
    );

// Finally, compute the voting outcomes. Note the gating of the `tie` output
// with a pre-computed constant expression, which eliminates that logic and
// replaces it with a constant zero when the number of votes is not even,
// since `tie` can never be valid in that case.

    always @(*) begin
        unanimity_zeros = (popcount == UNANIMITY_ZEROS);
        unanimity_ones  = (popcount == UNANIMITY_ONES);
        majority        = (popcount >= MAJORITY);
        minority        = (popcount <= MINORITY);
        tie             = (popcount == TIE) && (COUNT_IS_EVEN == 1'b1);
    end

endmodule

