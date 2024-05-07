
//# Pipeline Join (Lazy)

// Takes in multiple input ready/valid handshakes with associated data, and
// once all input handshakes can complete, joins them together into a single
// output ready/valid handshake with all data concatenated. This function
// synchronizes multiple pipelines into a single wider one.

//## Avoiding combinational loops

// As a design convention, we must avoid a combinational path between the
// valid and ready signals in a given pipeline interface, because if the other
// end of the pipeline connection also has a ready/valid combinational path,
// connecting these two interfaces will form a combinational loop, which
// cannot be analyzed for timing, or simulated reliably.

// However, there are rare cases where you do *not* want buffering, so if you
// take care about combinational delays and loops, you can use this unbuffered
// version. Otherwise, use the regular buffered [Pipeline Join]
// (./Pipeline_Join.html).

`default_nettype none

module Pipeline_Join_Lazy
#(
    parameter WORD_WIDTH     = 0,
    parameter INPUT_COUNT    = 0,

    // Do not set at instantiation, except in IPI
    parameter TOTAL_WIDTH   = WORD_WIDTH * INPUT_COUNT
)
(
    input  wire [INPUT_COUNT-1:0]   input_valid,
    output reg  [INPUT_COUNT-1:0]   input_ready,
    input  wire [TOTAL_WIDTH-1:0]   input_data,

    output reg                      output_valid,
    input  wire                     output_ready,
    output reg  [TOTAL_WIDTH-1:0]   output_data
);

    localparam INPUT_ZERO = {INPUT_COUNT{1'b0}};
    localparam INPUT_ONES = {INPUT_COUNT{1'b1}};
    localparam TOTAL_ZERO = {TOTAL_WIDTH{1'b0}};

    initial begin
        input_ready  = INPUT_ZERO;
        output_valid = 1'b0;
        output_data  = TOTAL_ZERO;
    end

// Once all inputs are valid, declare the output valid and make all the input
// ready equal to the output ready.  Pass the input data to the output data.

    always @(*) begin
        output_valid    = (input_valid == INPUT_ONES);
        output_data     = input_data;
    end

    always @(*) begin
        input_ready     = (output_valid == 1'b1) ? {INPUT_COUNT{output_ready}} : INPUT_ZERO;
    end

endmodule

