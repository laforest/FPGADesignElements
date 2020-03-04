
//# A Synchronous Register to Store and Control Data

// It may seem silly to implement a register module rather than let the HDL
// infer it, but doing so separates data and control at the most basic level,
// including various kinds of resets, which are part of control. This
// separation of data and control allows us to simplify the control logic and
// reduce the need for some routing resources.

//## Power-on-Reset
//
// On FPGAs, the initial state of registers is set in the configuration
// bitstream and applied by special power-on reset circuitry. The initial
// state of a design is available "for free" *and can be returned to at
// run-time*, which removes the need for that control and data logic.

//## Asynchronous Reset

// The asynchronous reset is not implemented here as its existence prevents
// register retiming, even if tied to zero. This limitation complicates design
// and reduces performance as we would have to manually place registers to
// properly pipeline logic. If you absolutely need an asynchronous reset for
// ASIC implementation or for some critical registers, use the
// [Register_areset](./Register_areset.html) instead.

//## Synchronous Reset (a.k.a. Clear)

// If you need to clear the register during normal operation, use the
// synchronous clear input. This may create extra logic, but that logic gets
// folded into other logic feeding data to the register, and would have been
// necessary anyway but present as another case in the surrounding logic.
// Having a clear input allows us to get to the initial power-on-reset state
// without complicating the design.

//## Implementation

// Let's begin with the usual front matter:

`default_nettype none

module Register
#(
    parameter WORD_WIDTH  = 0,
    parameter RESET_VALUE = 0
)
(
    input   wire                        clock,
    input   wire                        clock_enable,
    input   wire                        clear,
    input   wire    [WORD_WIDTH-1:0]    data_in,
    output  reg     [WORD_WIDTH-1:0]    data_out
);

    initial begin
        data_out = RESET_VALUE;
    end

// Here, we use the  "last assignment wins" idiom (See
// [Resets](./verilog.html#resets)) to implement reset.  This is also one
// place where we cannot use ternary operators, else the last assignment for
// clear (e.g.: `data_out <= (clear == 1'b1) ? RESET_VALUE : data_out;`) would
// override any previous assignment with the current value of `data_out` if
// `clear` is not asserted!

    always @(posedge clock) begin
        if (clock_enable == 1'b1) begin
            data_out <= data_in;
        end

        if (clear == 1'b1) begin
            data_out <= RESET_VALUE;
        end
    end

endmodule

