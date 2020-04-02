
//# Binary Carry-In Calculator

// Given two *binary* signed or unsigned integers (`A` and `B`) and their sum
// or difference (`sum`), returns the carry-in which happened at each bit
// position during the addition or subtraction.  You can use this on any
// matching subset of bits of `A`, `B`, and `sum`.

// Figuring out the carry-ins has uses for sub-word bit-parallel computations,
// such as determining if a vector byte addition overflowed into the adjacent
// byte, but the main use is to get the carry-in *into* the most-significant
// bit of a sum. Comparing the final carry-in with the final carry-out allows
// us to determine if a signed overflow occured, and to [compute other
// arithmetic predicates](./Arithmetic_Predicates_Binary.html) (e.g.:
// less-than, greater-than-or-equal, etc...)

`default_nettype none

module CarryIn_Binary
#(
    parameter WORD_WIDTH = 0
)
(
    input   wire    [WORD_WIDTH-1:0]    A,
    input   wire    [WORD_WIDTH-1:0]    B,
    input   wire    [WORD_WIDTH-1:0]    sum,
    output  reg     [WORD_WIDTH-1:0]    carryin
);

    initial begin
        carryin = {WORD_WIDTH{1'b0}};
    end

// Re-add the two integers without carries, which is merely XOR, then compare
// that carry-less sum with the input `sum` (this is also an XOR). If the sums
// differ, then a carry-in was present at that bit position during the input
// `sum`.

    always @(*) begin
        carryin = A ^ B ^ sum;
    end

endmodule

