
//# Pipeline Join

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

// Thus, the input interfaces here are buffered to break the combinational
// path, even if the buffering is redundant. It's not worth the risk of a bad
// simulation or synthesis otherwise.

`default_nettype none

module Pipeline_Join
#(
    parameter WORD_WIDTH     = 0,
    parameter INPUT_COUNT    = 0,

    // Do not set at instantiation, except in IPI
    parameter TOTAL_WIDTH   = WORD_WIDTH * INPUT_COUNT
)
(
    input  wire                     clock,
    input  wire                     clear,

    input  wire [INPUT_COUNT-1:0]   input_valid,
    output wire [INPUT_COUNT-1:0]   input_ready,
    input  wire [TOTAL_WIDTH-1:0]   input_data,

    output reg                      output_valid,
    input  wire                     output_ready,
    output reg  [TOTAL_WIDTH-1:0]   output_data
);

    localparam INPUT_ZERO = {INPUT_COUNT{1'b0}};
    localparam INPUT_ONES = {INPUT_COUNT{1'b1}};
    localparam TOTAL_ZERO = {TOTAL_WIDTH{1'b0}};

    initial begin
        output_valid = 1'b0;
        output_data  = TOTAL_ZERO;
    end

// First, we must buffer the input interfaces to break the combinational paths
// from valid to ready.

    wire [INPUT_COUNT-1:0]   input_valid_buffered;
    reg  [INPUT_COUNT-1:0]   input_ready_buffered = INPUT_ZERO;
    wire [TOTAL_WIDTH-1:0]   input_data_buffered;

    generate
        genvar j;
        for(j=0; j < INPUT_COUNT; j=j+1) begin: per_input
            Pipeline_Skid_Buffer
            #(
                .WORD_WIDTH         (WORD_WIDTH),
                .CIRCULAR_BUFFER    (0)             // Not meaningful here
            )
            input_buffer
            (
                .clock          (clock),
                .clear          (clear),
                
                .input_valid    (input_valid[j]),
                .input_ready    (input_ready[j]),
                .input_data     (input_data [WORD_WIDTH*j +: WORD_WIDTH]),
                
                .output_valid   (input_valid_buffered[j]),
                .output_ready   (input_ready_buffered[j]),
                .output_data    (input_data_buffered [WORD_WIDTH*j +: WORD_WIDTH])
            );
        end
    endgenerate

// Once all inputs are valid, declare the output valid and make all the input
// ready equal to the output ready.  Pass the input data to the output data.

    always @(*) begin
        output_valid            = (input_valid_buffered == INPUT_ONES);
        output_data             = input_data_buffered;
    end

    always @(*) begin
        input_ready_buffered    = (output_valid == 1'b1) ? {INPUT_COUNT{output_ready}} : INPUT_ZERO;
    end

endmodule

