
//# Variable Register Pipeline

// Delays a pipeline with variable shift-registers to adjust the latency 
// from input to output. The latency, in clock cycles, from input to output is
// selected by the `tap_number` control input, and has a maximum of
// `PIPE_DEPTH` cycles.  

// Each cycle `shift_data` is high, the pipeline shifts one word from
// `input_data` towards `output_data`. Pulse `tap_number_load` to set a new
// `tap_number`. `clear` sets all registers and the `tap_number` to zero. 

// **NOTE**: `PIPE_DEPTH` must be 16 or 32 to match the underlying AMD/Xilinx
// FPGA shift-register LUTs (SRLs). This should be trivial to port to other
// FPGA families.

// The `tap_number` is zero-indexed, so a `tap_number` of 0 selects the output
// of the first pipeline stage, and `PIPE_DEPTH-1` selects the output of the
// last pipeline stage. *It is not possible to select the input directly.*

// Changing the `tap_number` immediately changes the selected tap, and begins
// to output whatever data is at that point in the pipeline. Thus, you may
// skip data or (re)read old data.

`default_nettype none

module Register_Pipeline_Variable
#(
    parameter WORD_WIDTH = 0,
    parameter PIPE_DEPTH = 0,   // 16 or 32 only

    // Do not set at instantiation, except in Vivado IPI
    parameter ADDR_WIDTH = clog2(PIPE_DEPTH)
)
(
    input   wire                        clock,
    input   wire                        clear,

    input   wire                        tap_number_load,
    input   wire    [ADDR_WIDTH-1:0]    tap_number,

    input   wire                        shift_data,
    input   wire    [WORD_WIDTH-1:0]    input_data,
    output  wire    [WORD_WIDTH-1:0]    output_data
);

    `include "clog2_function.vh"

    localparam ADDR_ZERO    = {ADDR_WIDTH{1'b0}};

// First, store the tap selection address.

    wire [ADDR_WIDTH-1:0] tap_number_current;

    Register
    #(
        .WORD_WIDTH     (ADDR_WIDTH),
        .RESET_VALUE    (ADDR_ZERO)
    )
    tap_number_storage
    (
        .clock          (clock),
        .clock_enable   (tap_number_load),
        .clear          (clear),
        .data_in        (tap_number),
        .data_out       (tap_number_current)
    );

// Then instantiate SRL dynamic shift registers.

// We use the Xilinx SRLs because implementing this as a [Register Pipeline](./Register_Pipeline.html) and a 
// [Multiplexer](./Multiplexer_Binary_Behavioural.html) consumes a very large amount of
// area for what it does.

    generate
    genvar i;

        for (i = 0; i < WORD_WIDTH; i=i+1) begin: per_bit

            if (PIPE_DEPTH == 32) begin

                SRLC32E
                #(
                    .INIT(32'h00000000) // Initial Value of Shift Register
                )
                data_pipeline
                (
                  .Q    (output_data [i]),      // SRL data output
                  .Q31  (),                     // SRL cascade output pin
                  .A    (tap_number_current),   // 5-bit shift depth select input
                  .CE   (shift_data),           // Clock enable input
                  .CLK  (clock),                // Clock input
                  .D    (input_data [i])        // SRL data input
                );

            end
            else if (PIPE_DEPTH == 16) begin

                SRL16E
                #(
                    .INIT(16'h0000) // Initial Value of Shift Register
                )
                data_pipeline
                (
                  .Q        (output_data        [i]),   // SRL data output
                  .A0       (tap_number_current [0]),   // Select[0] input
                  .A1       (tap_number_current [1]),   // Select[1] input
                  .A2       (tap_number_current [2]),   // Select[2] input
                  .A3       (tap_number_current [3]),   // Select[3] input
                  .CE       (shift_data),               // Clock enable input
                  .CLK      (clock),                    // Clock input
                  .D        (input_data         [i])    // SRL data input
                );

            end

        end

    endgenerate

endmodule

