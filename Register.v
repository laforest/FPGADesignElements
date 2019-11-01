
// # A Synchronous Register to Store and Control Data

// It may seem silly to implement a register module rather than let the HDL
// infer it, but doing so separates data and control at the most basic level,
// including various kinds of resets, which are part of control. This
// separation of data and control allows us to simplify the control logic and
// reduce the need for some routing resources.

// ## Power-on-Reset
//
// On FPGAs, the initial state of registers is set in the configuration
// bitstream and applied by special power-on reset circuitry. The initial
// state of a design is available "for free" *and can be returned to at
// run-time*, which removes the need for that control and data logic.

// ## Asynchronous Reset

// On FPGAs, the hardware reset of a flip-flop is usually asynchronous and so
// takes effect immediately rather than at the next clock edge, which can
// cause subtle bugs: a register appears to fail to capture data in
// behavioural simulation, or changes in impossible ways (within less than
// a clock cycle) in timing-annotated post-synthesis simulation.  Where
// possible, avoid the use of the asynchronous reset and instead depend on the
// power-on-reset to initially load the reset value. This reduces the size of
// the reset network and simplifies place-and-route.

// The asynchronous reset is necessary to force a register reset where the
// control logic to the register(s) might be stuck. It is necessary to feed the
// reset from a clock-sychronous source so registers don't flip value close to
// the metastability window of a downstream register.

// ## Synchronous Reset (a.k.a. Clear)

// If you need to clear the register during normal operation, use the
// synchronous clear input. This may create extra logic, but that logic gets
// folded into other logic feeding data to the register, and would have been
// necessary anyway but present as another case in the surrounding logic.
// Having a clear input allows us to get to the initial power-on-reset state
// without complicating the design.

// ## Implementation

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
    input   wire                        areset,
    input   wire                        clear,
    input   wire    [WORD_WIDTH-1:0]    data_in,
    output  reg     [WORD_WIDTH-1:0]    data_out
);

    initial begin
        data_out = RESET_VALUE;
    end

// Normally, I would use the "last assignment wins" idiom (See
// [Resets](./verilog.html#resets) in the [Verilog Coding
// Standard](./verilog.html)) to implement reset, but that doesn't work
// here: having two separate if-statements (one for clock_enable followed
// by one for reset) does not work when the reset is asynchronously
// specified in the sensitivity list (as done here), as there is no way to
// determine which signal in the sensitivity list each if statement should
// respond to.

// Thus, correct hardware inference depends on explicitly expressing the
// priority of the reset over the clock_enable structurally with nested
// if-statements, rather than implicitly through the Verilog event queue
// via the "last assignment wins" idiom.

// This is very likely the *only* place you will ever need an asynchronous
// signal in a sensitivity list, or express explicit structural priority.

    reg [WORD_WIDTH-1:0] selected = RESET_VALUE;

    always @(*) begin
        selected = (clear == 1'b1) ? RESET_VALUE : data_in;
    end

    always @(posedge clock or posedge areset) begin
        if (areset == 1'b1) begin
            data_out <= RESET_VALUE;
        end
        else begin
            if ((clock_enable == 1'b1) || (clear == 1'b1)) begin
                data_out <= selected;
            end
        end
    end

endmodule

