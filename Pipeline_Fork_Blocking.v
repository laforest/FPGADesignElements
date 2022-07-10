
//# Pipeline Fork (Blocking)

// Takes in a ready/valid handshake with the associated data, and replicates
// that transaction to multiple outputs. The input can proceed to the next
// transaction once **all** outputs can finish their transactions
// **simultaneously**. This constraint prevents any branch from running ahead
// of the others.

// **NOTE**: If the downstream logic connected to the output interfaces can
// lower their `ready` signal after raising it, before the corresponding
// `valid` is raised to complete the handshake, you could end up with
// deadlocks of unknown duration until all `ready` signals happen to be
// asserted together. To avoid this situation, use an [Eager Pipeline
// Fork](./Pipeline_Fork_Eager.html), but then you cannot guarantee lockstep
// operation of the various downstream logic branches.

// The input is buffered to minimise any long combinational path or loops
// which might happen when using the [Lazy Pipeline
// Fork](./Pipeline_Fork_Lazy.html).

`default_nettype none

module Pipeline_Fork_Blocking
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

    wire                    input_valid_buffered;
    wire                    input_ready_buffered;
    wire [WORD_WIDTH-1:0]   input_data_buffered;

    Pipeline_Skid_Buffer
    #(
        .WORD_WIDTH     (WORD_WIDTH)
    )
    input_buffer
    (
        .clock           (clock),
        .clear           (clear),

        .input_valid     (input_valid),
        .input_ready     (input_ready),
        .input_data      (input_data),

        .output_valid    (input_valid_buffered),
        .output_ready    (input_ready_buffered),
        .output_data     (input_data_buffered)
    );

    Pipeline_Fork_Lazy
    #(
        .WORD_WIDTH     (WORD_WIDTH),
        .OUTPUT_COUNT   (OUTPUT_COUNT)
    )
    output_fork
    (
        .input_valid    (input_valid_buffered),
        .input_ready    (input_ready_buffered),
        .input_data     (input_data_buffered),

        .output_valid   (output_valid),
        .output_ready   (output_ready),
        .output_data    (output_data)
    );

endmodule

