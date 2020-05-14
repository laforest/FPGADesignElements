
//# Signed Binary Accumulator

// Adds the signed `increment` to the signed `accumulated_value` every cycle
// `increment_valid` is high. `load_valid` overrides `increment_valid` and
// instead loads the accumulator with `load_value`. `clear` overrides both
// `increment_valid` and `load_valid` and puts the accumulator back at
// `INITIAL_VALUE`.

// If the accmulator increments past the max or min signed integer value it
// can hold, the accumulator will roll-over and set the `signed_overflow` bit.
// The overflow bit is cleared at the next non-overflowing increment, or if
// the accumulator is cleared or loaded.

// When chaining accumulators, which may happen if you are incrementing in
// unusual bases where each digit has its own accumulator, AND the `carry_out`
// of the previous accumulator with the signal fed to the `increment_valid`
// input of the next accumulator. The `carry_in` is kept for generality.

`default_nettype none

module Accumulator_Binary
#(
    parameter                   WORD_WIDTH      = 0,
    parameter [WORD_WIDTH-1:0]  INITIAL_VALUE   = 0
)
(
    input   wire                        clock,
    input   wire                        clear,
    input   wire    [WORD_WIDTH-1:0]    increment,
    input   wire                        increment_valid,
    input   wire    [WORD_WIDTH-1:0]    load_value,
    input   wire                        load_valid,
    input   wire                        carry_in,
    output  wire                        carry_out,
    output  wire    [WORD_WIDTH-1:0]    accumulated_value,
    output  wire                        signed_overflow
);

    localparam WORD_ZERO = {WORD_WIDTH{1'b0}};

// Apply the increment to the current accumulator value.

    wire [WORD_WIDTH-1:0] incremented_value;

    Adder_Subtractor_Binary
    #(
        .WORD_WIDTH (WORD_WIDTH)
    )
    add_increment
    (
        .add_sub    (1'b0), // 0/1 -> A+B/A-B
        .carry_in   (carry_in),
        .A_in       (accumulated_value),
        .B_in       (increment),
        .sum_out    (incremented_value),
        .carry_out  (carry_out)
    );

// Then, let's [reconstruct the carry-in](./CarryIn_Binary.html) into the last
// (most-significant) bit position of the result. If it differs from the
// carry_out, then a signed overflow/underflow happened, where we either added
// past the largest positive value or subtracted past the smallest negative
// value.

    wire final_carry_in;

    CarryIn_Binary
    #(
        .WORD_WIDTH (1)
    )
    calc_final_carry_in
    (
        .A          (accumulated_value  [WORD_WIDTH-1]),
        .B          (increment          [WORD_WIDTH-1]),
        .sum        (incremented_value  [WORD_WIDTH-1]),
        .carryin    (final_carry_in)
    );

    reg signed_overflow_internal = 1'b0;

    always @(*) begin
        signed_overflow_internal = (carry_out != final_carry_in);
    end

// Update the accumulator if load or increment is valid. 
// *Load overrides increment.* 
// Clear the overflow if loading.

    reg [WORD_WIDTH-1:0]    next_value              = WORD_ZERO;
    reg                     enable_accumulator      = 1'b0;
    reg                     enable_overflow         = 1'b0;
    reg                     clear_overflow          = 1'b0;

    always @(*) begin
        next_value          = (load_valid == 1'b1) ? load_value : incremented_value;
        enable_accumulator  = (increment_valid == 1'b1) || (load_valid == 1'b1);
        enable_overflow     = (increment_valid == 1'b1);
        clear_overflow      = (load_valid      == 1'b1) || (clear      == 1'b1);
    end

// Finally, the accumulator and signed_overflow registers.

    Register
    #(
        .WORD_WIDTH     (WORD_WIDTH),
        .RESET_VALUE    (INITIAL_VALUE)
    )
    accumulator
    (
        .clock          (clock),
        .clock_enable   (enable_accumulator),
        .clear          (clear),
        .data_in        (next_value),
        .data_out       (accumulated_value)
    );

    Register
    #(
        .WORD_WIDTH     (1),
        .RESET_VALUE    (1'b0)
    )
    overflow
    (
        .clock          (clock),
        .clock_enable   (enable_overflow),
        .clear          (clear_overflow),
        .data_in        (signed_overflow_internal),
        .data_out       (signed_overflow)
    );

endmodule

