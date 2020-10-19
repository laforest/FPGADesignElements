//# Weinstein Flancter

// A Flancter allows you to set a bit in one clock domain, and reset the same
// bit from another clock domain, without using an asynchronous reset, and
// without the set/reset operation depending on the other clock.

// In most cases, you can get the same functionality with simpler CDC
// behaviour and control logic by using a [CDC Flag Bit](./CDC_Flag_Bit.html).

//## Operation

// Pulse `bit_set` for one `clock_set` cycle to raise `bit_out`, and pulse
// `bit_reset` for one `clock_reset` cycle to lower `bit_out`. Raise *both*
// `clear_set` and `clear_reset` for at least one cycle in each clock domain
// (`clock_set` and `clock_reset`) to reset the entire Flancter, else
// `bit_out` may unexpectedly set rather than clear. Depending on your
// application, you may need to use [Registers with asynchronous
// resets](./Register_areset.html) instead.

//## Operating Conditions

// A Flancter needs supporting control and CDC circuitry to be usable, and
// requires more work in the CAD tool to properly constrain and analyze
// timing. See the related [References and Reading List
// entry](./reading.html#flancter) for details, links, and application notes.

// The primary operating condition is that the `bit_set` and `bit_reset`
// signals must never overlap, or be in each other's setup/hold windows, since
// set/reset are asynchronous to each other. To guarantee such overlaps cannot
// happen: once set, the Flancter must not be set again until reset, and
// once reset, must not be reset again until set.

`default_nettype none

module Weinstein_Flancter
(
    input   wire    clock_set,
    input   wire    clear_set,
    input   wire    bit_set,

    input   wire    clock_reset,
    input   wire    clear_reset,
    input   wire    bit_reset,

    output  reg     bit_out
);

    initial begin
        bit_out = 1'b0;
    end

// When enabled, the output of `register_set` takes on the *opposite* value of
// the output of `register_reset`. This only happens in the `clock_set`
// domain.

    wire register_reset_data;
    wire register_set_data;

    Register
    #(
        .WORD_WIDTH     (1),
        .RESET_VALUE    (1'b0)
    )
    register_set
    (
        .clock          (clock_set),
        .clock_enable   (bit_set),
        .clear          (clear_set),
        .data_in        (~register_reset_data),
        .data_out       (register_set_data)
    );

// When enabled, the output of `register_reset` takes on the the value of the
// output of `register_set`. This only happens in the `clock_reset` domain.

    Register
    #(
        .WORD_WIDTH     (1),
        .RESET_VALUE    (1'b0)
    )
    register_reset
    (
        .clock          (clock_reset),
        .clock_enable   (bit_reset),
        .clear          (clear_reset),
        .data_in        (register_set_data),
        .data_out       (register_reset_data)
    );

// When the two register outputs differ, the `bit_out` is set. **Note that
// `bit_out` must be considered asynchronous to both clock domains**, and must
// be run through a [CDC Bit Synchronizer](./CDC_Bit_Synchronizer.html) before
// being used.

    always @(*) begin
        bit_out = register_set_data != register_reset_data;
    end

endmodule

