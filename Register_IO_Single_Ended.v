
//# A Single-Ended Input/Output Register 

// This register samples an input with an incoming external clock, or updates
// an output with an outgoing internal clock. We use Verilog attributes to
// tell the CAD tool to place the register in I/O register locations at the
// edges of the FPGA, thus minimizing any skew.

// This module is a specialization of the simple [Synchronous
// Register](./Register.html) module, since we must apply the attributes
// directly to the HDL register and not the module as a whole. See the
// Synchronous Register module for further documentation and discussion.

// **NOTE**: *Under Vivado, using a `DONT_TOUCH` or `KEEP` attribute or
// constraint on this module, or the `data_reg` register, will prevent the
// `IOB` attribute from taking effect. Thus the register may end up not packed
// into an IOB location.*

//## Ports and Parameters

`default_nettype none

module Register_IO_Single_Ended
#(
    parameter                   WORD_WIDTH  = 0,
    parameter [WORD_WIDTH-1:0]  RESET_VALUE = 0
)
(
    input   wire                        clock,
    input   wire                        clock_enable,
    input   wire                        clear,
    input   wire    [WORD_WIDTH-1:0]    data_in,
    output  reg     [WORD_WIDTH-1:0]    data_out
);

    // For simulation. Not driven by a clock.

    initial begin
        data_out = RESET_VALUE;
    end

//## Registers with attributes

    // Quartus
    (* useioff = 1 *)
    // Vivado
    (* IOB = "TRUE" *)

    reg [WORD_WIDTH-1:0] data_reg = RESET_VALUE;

//## Clocking, Reset, and Output

// Here, we use the  "last assignment wins" idiom (See
// [Resets](./verilog.html#resets)) to implement reset.  This is also one
// place where we cannot use ternary operators, else the last assignment for
// clear (e.g.: `data_out <= (clear == 1'b1) ? RESET_VALUE : data_out;`) would
// override any previous assignment with the current value of `data_out` if
// `clear` is not asserted!

    always @(posedge clock) begin
        if (clock_enable == 1'b1) begin
            data_reg <= data_in;
        end

        if (clear == 1'b1) begin
            data_reg <= RESET_VALUE;
        end
    end

    always @(*) begin
        data_out = data_reg;
    end

endmodule

