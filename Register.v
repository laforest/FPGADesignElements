
// # A Synchronous Register to Store Data.

// It may seem silly to explicitly implement a register rather than let the
// HDL infer it, but having the register as a module solves the problem of
// forgetting to set the initial and reset value, and of resetting only the
// registers that need resetting, thus reducing the routing and timing
// requirements of the reset tree.

// Also, a register module separates control from data with explicit signals
// to load and clear the register.

// On FPGAs, the flip-flop hardware reset is usually asynchronous, and so can
// be used as a forced system reset, but must be fed from a clock-synchronous
// signal under normal operation. This means if a complete system reset is
// required after the initial power-up reset, erasing all current state, it
// can be asserted asynchronously if you want, but must be deasserted
// synchronously.  A partial reset of the system must be synchronous. Better
// to always have a synchronous reset.

// If at all possible, avoid using the "areset" pin (tie it low), and instead
// depend on the initial power-up reset (on FPGAs) to load the reset value.
// This reduces the size of the reset network and simplifies place-and-route.

// If you need to clear a register during normal operation, use the
// synchronous "clear" input. This may create extra logic, but abstracts away
// that case from the surrounding logic. The asynchronous reset takes effect
// immediately, before any clock edge, which shows up as impossible "missing"
// register loads in a behavioural simulation, and impossible
// shorter-than-the-clock-period pulses, almost glitches, in
// a timing-annotated post-synthesis simulation.

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
    input   wire    [WORD_WIDTH-1:0]    in,
    output  reg     [WORD_WIDTH-1:0]    out
);

    initial begin
        out = RESET_VALUE;
    end

    // Normally, I would use the ["last assignment wins"](./verilog.html#resets)
    // idiom to implement reset, but that doesn't work here: the reset signal
    // into the flip-flop hardware is asynchronous usually. Forcing
    // a synchronous reset converts the reset to extra logic feeding the
    // flip-flop data pin. (That's what the "clear" pin is for.)

    // Also, having two separate if-statements (one for clock_enable followed
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

    // The synchronous clear implements as logic in front of the register,
    // which will merge with the logic feeding the "in" and "clock_enable"
    // pin, without external logic having to multiplex a "clear" value into
    // "in".

    reg [WORD_WIDTH-1:0] selected = RESET_VALUE;

    always @(*) begin
        selected = (clear == 1'b1) ? RESET_VALUE : in;
    end

    always @(posedge clock or posedge areset) begin
        if (areset == 1'b1) begin
            out <= RESET_VALUE;
        end
        else begin
            if ((clock_enable == 1'b1) || (clear == 1'b1)) begin
                out <= selected;
            end
        end
    end

endmodule

