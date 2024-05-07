
//# Pipeline Synchronizer (Lazy)

// Takes in two or more pipelines and synchronizes them so they can only
// complete their handshakes simultaneously, then outputs the synchronized
// handshakes. This forces data to be consumed in FIFO order and in lock-step
// for all pipelines (e.g.: addresses and data for a memory write, each from
// independent sources).

// We synchronize by first Joining the pipelines, then re-forking them and
// discarding all but one copy of the data.

// A consequence of the synchronization is that the ready signal of the input
// interfaces will only assert once *all* input valid lines are asserted. This
// is a combinational path. There is no buffering. Watch out for combinational
// loops.

//## Ports, Parameters, and Constants

`default_nettype none

module Pipeline_Synchronizer_Lazy
#(
    parameter WORD_WIDTH        = 0,
    parameter PORT_COUNT        = 0,

    // Do not set at instantiation, except in Vivado IPI
    parameter PORT_WIDTH_TOTAL  = WORD_WIDTH * PORT_COUNT
)
(
    output  wire    [PORT_COUNT-1:0]        input_data_ready,
    input   wire    [PORT_COUNT-1:0]        input_data_valid,
    input   wire    [PORT_WIDTH_TOTAL-1:0]  input_data,

    input   wire    [PORT_COUNT-1:0]        output_data_ready,
    output  wire    [PORT_COUNT-1:0]        output_data_valid,
    output  reg     [PORT_WIDTH_TOTAL-1:0]  output_data
);

    localparam PORT_WIDTH_TOTAL_ZERO = {PORT_WIDTH_TOTAL{1'b0}};

    initial begin
        output_data = PORT_WIDTH_TOTAL_ZERO;
    end

//## Input Join

    wire                        input_data_joined_valid;
    wire                        input_data_joined_ready;
    wire [PORT_WIDTH_TOTAL-1:0] input_data_joined;

    Pipeline_Join_Lazy
    #(
        .WORD_WIDTH     (WORD_WIDTH),
        .INPUT_COUNT    (PORT_COUNT)
    )
    input_join
    (
        .input_valid    (input_data_valid),
        .input_ready    (input_data_ready),
        .input_data     (input_data),

        .output_valid   (input_data_joined_valid),
        .output_ready   (input_data_joined_ready),
        .output_data    (input_data_joined)
    );

//## Output Fork

// We end up with duplicates of the input data since we are creating
// `PORT_COUNT` forked copies of all the `PORT_COUNT` input data interfaces
// joined together. So we discard all but the first copy and keep all the
// control signals.

    localparam PORT_WIDTH_TOTAL_WITH_DUPLICATES = PORT_WIDTH_TOTAL * PORT_COUNT;

    // verilator lint_off UNUSED
    wire [PORT_WIDTH_TOTAL_WITH_DUPLICATES-1:0] output_data_with_duplicates;
    // verilator lint_on  UNUSED

    Pipeline_Fork_Lazy
    #(
        .WORD_WIDTH     (PORT_WIDTH_TOTAL),
        .OUTPUT_COUNT   (PORT_COUNT)
    )
    output_fork
    (
        .input_valid    (input_data_joined_valid),
        .input_ready    (input_data_joined_ready),
        .input_data     (input_data_joined),

        .output_valid   (output_data_valid),
        .output_ready   (output_data_ready),
        .output_data    (output_data_with_duplicates)
    );

    always @(*) begin
        output_data = output_data_with_duplicates [0 +: PORT_WIDTH_TOTAL];
    end

endmodule

