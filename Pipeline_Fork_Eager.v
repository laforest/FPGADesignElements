
//# Pipeline Fork (Eager)

// Takes in a ready/valid handshake with the associated data, and replicates
// that transaction to multiple outputs. The input can proceed to the next
// transaction once **all** outputs have finished their transactions.  *Each
// output transaction can complete independently.*

// The outputs are buffered, so each output transaction can complete
// independently, in any order. This also breaks any long combinational path
// or loops which might happen when using the [Lazy Pipeline
// Fork](./Pipeline_Fork_Lazy.html).

`default_nettype none

module Pipeline_Fork_Eager
#(
    parameter WORD_WIDTH    = 0,
    parameter OUTPUT_COUNT  = 0,

    // Do not set at instantiation, except in IPI
    parameter TOTAL_WIDTH   = WORD_WIDTH * OUTPUT_COUNT
)
(
    input  wire                     clock,
    input  wire                     clear,

    input  wire                     input_valid,
    output wire                     input_ready,
    input  wire [WORD_WIDTH-1:0]    input_data,

    output wire [OUTPUT_COUNT-1:0]  output_valid,
    input  wire [OUTPUT_COUNT-1:0]  output_ready,
    output wire [TOTAL_WIDTH-1:0]   output_data
);

    wire [OUTPUT_COUNT-1:0] output_valid_unbuffered;
    wire [OUTPUT_COUNT-1:0] output_ready_unbuffered;
    wire [TOTAL_WIDTH-1:0]  output_data_unbuffered;

    Pipeline_Fork_Lazy
    #(
        .WORD_WIDTH     (WORD_WIDTH),
        .OUTPUT_COUNT   (OUTPUT_COUNT)
    )
    input_fork
    (
        .input_valid    (input_valid),
        .input_ready    (input_ready),
        .input_data     (input_data),

        .output_valid   (output_valid_unbuffered),
        .output_ready   (output_ready_unbuffered),
        .output_data    (output_data_unbuffered)
    );

    generate
        genvar i;
        for (i=0; i < OUTPUT_COUNT; i=i+1) begin: per_output
            Pipeline_Skid_Buffer
            #(
                .WORD_WIDTH      (WORD_WIDTH),
                .CIRCULAR_BUFFER (0)            // Not meaningful here
            )
            output_buffer
            (
                .clock           (clock),
                .clear           (clear),

                .input_valid     (output_valid_unbuffered [i]),
                .input_ready     (output_ready_unbuffered [i]),
                .input_data      (output_data_unbuffered  [WORD_WIDTH*i +: WORD_WIDTH]),

                .output_valid    (output_valid [i]),
                .output_ready    (output_ready [i]),
                .output_data     (output_data  [WORD_WIDTH*i +: WORD_WIDTH])
            );
        end
    endgenerate

endmodule

