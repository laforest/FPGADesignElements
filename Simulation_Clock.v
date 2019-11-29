
//# Simulation Clock

// *This text is mostly lifted from the [Simulated Clock
// Generation](./verilog.html#clock) section of my Verilog Coding Standard.
// Credit goes to Clifford Wolf ([@oe1cxw](https://twitter.com/oe1cxw)) for
// teaching me this finer point of Verilog simulation.*

// **NOTE: This code cannot work in Verilator, which can only simulate
// synthesizable Verilog, and thus does not support delayed assignments.**
// Simulate the clock in the C++ testbench instead, or if you must use
// Verilog, try the Icarus Verilog simulator.

// In simulation, a race condition can exist at time zero between the initial
// value assignment of a register and the first clock edge. For example:

//    reg clock = 1'b0; // Counts as a negedge at time zero! (1'bX -> 1'b0)
//    reg foo   = 1'b0; // Also does 1'bX -> 1'b0 at time zero.
//    reg bar   = 1'b0;
//
//    // Simulate the clock
//    always begin
//        #HALF_PERIOD clock = ~clock;
//    end
//
//    // Use the simulated clock
//    always @(negedge clock) begin
//        bar <= foo;
//    end

// In the code above, it is unclear if the initial negative clock edge or the
// initialization of `foo` will simulate first, so `bar` might get assigned
// 1'bX for the first simulation cycle, which is not what the code intends.
// This race condition is another reason to only use `@(posedge clock)` in
// internal logic, but the same race condition will happen if the simulation
// clock happens to be initialized to 1'b1.

// Instead, the following clock simulation idiom avoids the race condition by
// making use of undefined values and the identity operator `===`, which
// matches X values exactly, instead of the equality `==` operator which
// treats X as false: we leave the clock uninitialized to 1'bX, and compare it
// by identity after one clock half-period delay, which then assigns it false
// (1'b0).

`default_nettype none

module Simulation_Clock
#(
    parameter CLOCK_PERIOD = 10
)
(
    output reg clock
);

    localparam HALF_PERIOD = CLOCK_PERIOD / 2;

    always begin
        #HALF_PERIOD clock = (clock === 1'b0);
    end

endmodule

// Additionally, the following tidbits are handy to use with the resulting clock:

//    `define WAIT_CYCLES(n) repeat (n) begin @(posedge clock); end
//
//    time cycle = 0; 
//
//    always @(posedge clock) begin
//        cycle = cycle + 1;
//    end
//
//    `define UNTIL_CYCLE(n) wait (cycle == n);

