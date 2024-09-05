//# IDELAYCTRL: A controller for IDELAY2 blocks

// **This module is specific to Series 7 AMD/Xilinx FPGA devices.**
// Instantiates an IDELAYCTRL block for automatically calibrating the delay
// line in the IDELAY2 programmable delay blocks in an I/O Bank.  IDELAY2s are
// typically used with high-speed interfaces where the delay across multiple
// I/O pins must be fine-tuned to match in the sub-nanosecond range.

// This is a trivial wrapper module, but it does convert a Verilog attribute
// on the module instance into a parameter, which makes for a cleaner
// composition into larger designs.

//## Usage

// One IDELAYCTRL is needed per I/O Bank and the controlled IDELAY2 blocks
// must be in the same `IODELAY_GROUP`.  If `ready` drops then calibration was
// lost, likely due to a `reference_clock` glitch: reset and retrain your
// interface logic.  See the "*7 Series FPGAs SelectIO Resources User Guide
// (UG471)*" for details on the allowable reference clock frequency ranges.

`default_nettype none

module IDELAYCTRL_Instance
#(
    parameter IODELAY_GROUP     = ""    // Must match with the IDELAY2 blocks
)
(
    input  wire                 reference_clock,    // See UG471 for allowable frequency ranges
    input  wire                 reset,
    output wire                 ready               // If this drops, reset and retrain
);


    (* IODELAY_GROUP = IODELAY_GROUP *) // Specifies group name for associated IDELAY2s/ODELAY2s and IDELAYCTRL

    IDELAYCTRL 
    idelay2_control (
        .RDY    (ready),            // 1-bit output: Ready output
        .REFCLK (reference_clock),  // 1-bit input:  Reference clock input
        .RST    (reset)             // 1-bit input:  Active high reset input
    );

endmodule

