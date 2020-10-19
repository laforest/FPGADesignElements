//# CDC Flag Bit

// Implements a flag bit which is set in one clock domain and cleared from
// another clock domain, without any asynchronous resets, and with simpler CDC
// behaviour and control than a Flancter.

// This design is derived from [Rob Weinstein's Flancter
// design](./Weinstein_Flancter.html), but synchronizes all signals crossing
// clock domains, which makes it simpler to ensure it works correctly. The
// synchronization also frees us from the constraint that set and reset must
// never be asserted at the same time or within each others setup/hold window.

// On the other hand, this circuit isn't *quite* equivalent to a Flancter as
// it depends on both clock domains to be always running for the synchronizers
// to pass values, while a Flancter does not (e.g.: we can still reset
// a Flancter even if the set clock is not running).  Depending on your
// application, you may need to use [Registers with asynchronous
// resets](./Register_areset.html) instead.

//## Operation

// Pulse `bit_set` for one `clock_set` cycle to raise `bit_out_set` (and then
// `bit_out_reset`), and pulse `bit_reset` for one `clock_reset` cycle to
// lower `bit_out_reset` (and then `bit_out_set`).  **A set or reset is
// immediately visible in its own domain, then propagates to the other domain
// after the usual CDC synchronization delay.** A set operation while already
// set, or a reset operation while already reset, is allowable and has no
// effect. 

// Raise both `clear_set` and `clear_reset` *together* for at least `4
// + EXTRA_CDC_STAGES` cycles in each clock domain (`clock_set` and
// `clock_reset`) to reset the entire CDC Flag Bit, else `bit_out_set` and/or
// `bit_out_reset` may unexpectedly set rather than clear.

// Adjust the `EXTRA_CDC_STAGES` parameter if you are running near the
// speed/temperature limits of your device. Consult your vendor datasheets.

`default_nettype none

module CDC_Flag_Bit
#(
    parameter EXTRA_CDC_STAGES = 0
)
(
    input   wire    clock_set,
    input   wire    clear_set,
    input   wire    bit_set,
    output  reg     bit_out_set,

    input   wire    clock_reset,
    input   wire    clear_reset,
    input   wire    bit_reset,
    output  reg     bit_out_reset
);

    initial begin
        bit_out_set   = 1'b0;
        bit_out_reset = 1'b0;
    end

// The `setting_bit` and `resetting_bit` Registers together form a toggle
// register but split into two parts, one in each clock domain (set and
// reset), whose relative difference expresses the value of the CDC flag bit.

// Raising `bit_set` makes the output of `setting_bit` take the **opposite**
// value of the synchronised `resetting_bit` output, which signifies a flag
// value of one.

    wire reset_toggle_synced;
    wire set_toggle;

    Register
    #(
        .WORD_WIDTH     (1),
        .RESET_VALUE    (1'b0)
    )
    setting_bit
    (
        .clock          (clock_set),
        .clock_enable   (bit_set),
        .clear          (clear_set),
        .data_in        (~reset_toggle_synced),
        .data_out       (set_toggle)
    );

// We then sync the `set_toggle` into the reset clock domain.

    wire set_toggle_synced;

    CDC_Bit_Synchronizer
    #(
        .EXTRA_DEPTH        (EXTRA_CDC_STAGES)  // Must be 0 or greater
    )
    set_to_reset
    (
        .receiving_clock    (clock_reset),
        .bit_in             (set_toggle),
        .bit_out            (set_toggle_synced)
    );

// And use the `set_toggle_synced` as the input to the `resetting_bit`.
// Raising `bit_reset` makes the output of `resetting_bit` match that of the
// synchronized version of `setting_bit`, which signifies a flag value of
// zero.

    wire reset_toggle;

    Register
    #(
        .WORD_WIDTH     (1),
        .RESET_VALUE    (1'b0)
    )
    resetting_bit
    (
        .clock          (clock_reset),
        .clock_enable   (bit_reset),
        .clear          (clear_reset),
        .data_in        (set_toggle_synced),
        .data_out       (reset_toggle)
    );

// Then we sync the `reset_toggle` into the set clock domain.

    CDC_Bit_Synchronizer
    #(
        .EXTRA_DEPTH        (EXTRA_CDC_STAGES)  // Must be 0 or greater
    )
    reset_to_set
    (
        .receiving_clock    (clock_set),
        .bit_in             (reset_toggle),
        .bit_out            (reset_toggle_synced)
    );

// Finally, in each clock domain, if the set and reset toggles differ, the
// flag is one. If they are the same, the flag is zero. The toggles, and thus
// the output bits, will eventually always match after CDC completes.

    always @(*) begin
        bit_out_set   = (set_toggle        != reset_toggle_synced);
        bit_out_reset = (set_toggle_synced != reset_toggle);
    end

endmodule

