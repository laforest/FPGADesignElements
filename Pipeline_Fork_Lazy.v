
//# Pipeline Fork (Lazy)

// Takes in a ready/valid handshake along with the associated data, and
// replicates that transaction to multiple outputs. The input can proceed to
// the next transaction once **all** outputs have finished their transactions.
// *All input and output transactions complete simultaneously.*

// There is no buffering, so be careful of combinational paths. If you cannot
// avoid a long combination path (or worse, a loop), then you must use the
// [Eager Pipeline Fork](./Pipeline_Fork_Eager.html).

`default_nettype none

module Pipeline_Fork_Lazy
#(
    parameter WORD_WIDTH    = 0,
    parameter OUTPUT_COUNT  = 0,

    // Do not set at instantiation, except in IPI
    parameter TOTAL_WIDTH   = WORD_WIDTH * OUTPUT_COUNT
)
(
    input  wire                     input_valid,
    output reg                      input_ready,
    input  wire [WORD_WIDTH-1:0]    input_data,

    output reg  [OUTPUT_COUNT-1:0]  output_valid,
    input  wire [OUTPUT_COUNT-1:0]  output_ready,
    output reg  [TOTAL_WIDTH-1:0]   output_data
);

    localparam TOTAL_ZERO   = {TOTAL_WIDTH{1'b0}};
    localparam OUTPUT_ONES  = {OUTPUT_COUNT{1'b1}};
    localparam OUTPUT_ZERO  = {OUTPUT_COUNT{1'b0}};

    initial begin
        input_ready     = 1'b0;
        output_valid    = OUTPUT_ZERO;
        output_data     = TOTAL_ZERO;
    end

// If all outputs are ready, then signal ready to the input and pass the valid
// signal through to all outputs, so all transaction complete together.

    reg output_valid_gated  = 1'b0;

    always @(*) begin
        input_ready         = (output_ready == OUTPUT_ONES);
        output_valid_gated  = (input_valid == 1'b1) && (input_ready == 1'b1);
        output_valid        = {OUTPUT_COUNT{output_valid_gated}};
        output_data         = {OUTPUT_COUNT{input_data}};
    end

endmodule

