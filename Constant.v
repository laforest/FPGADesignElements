
//# A Constant Value Output
//
// Normally this is merely a `localparam` inside another module, but it may
// be useful implemented as a module on its own to work with other IP systems
// such as Xilinx's IPI (IP Integrator), where you may need to feed an IP
// block a constant value.

`default_nettype none

module Constant
#(
    parameter WORD_WIDTH    = 0,
    parameter VALUE         = 0
)
(
    output wire [WORD_WIDTH-1:0] constant_out
);

    assign constant_out = VALUE;

endmodule

