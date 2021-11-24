
//# Skid Buffer Pipeline

// Pipelines the path of a ready/valid handshake with zero or more [Skid
// Buffers](./Pipeline_Skid_Buffer.html) to control the propagation delay and
// increase the possible clock frequency. The latency from input to output is
// `PIPE_DEPTH` cycles. This module is a variation of the [Simple Register
// Pipeline](./Register_Pipeline_Simple.html).

// Unlike a [Pipeline FIFO Buffer](./Pipeline_FIFO_Buffer.html), a Skid Buffer
// Pipeline will not improve concurrency by absorbing any irregularities in
// the transfer rates of the input and output interfaces: if one interface
// stalls, the other interface will eventually see that stall. However, a FIFO
// buffer will not add much pipelining.

// Alternatively, if you can afford a FIFO or if your hardware supports it
// well, you may want to use a [Pipeline Credit
// Buffer](./Pipeline_Credit_Buffer.html) instead, which might use less
// hardware for longer pipelines and has both the pipelining benefits of
// a Skid Buffer Pipeline and the buffering of a FIFO.

// `clear` sets all registers to zero. If `PIPE_DEPTH` is zero, the input
// handshake ports becomes directly wired to the output handshake ports and no
// logic is inferred.

`default_nettype none

module Skid_Buffer_Pipeline
#(
    parameter WORD_WIDTH =  0,
    parameter PIPE_DEPTH = -1
)
(
    // If PIPE_DEPTH is zero, these are unused
    // verilator lint_off UNUSED
    input   wire                        clock,
    input   wire                        clear,
    // verilator lint_on  UNUSED
    input   wire                        input_valid,
    output  wire                        input_ready,
    input   wire    [WORD_WIDTH-1:0]    input_data,

    output  reg                         output_valid,
    input   wire                        output_ready,
    output  reg     [WORD_WIDTH-1:0]    output_data
);

    localparam WORD_ZERO = {WORD_WIDTH{1'b0}};

    initial begin
        output_valid = 1'b0;
        output_data  = WORD_ZERO;
    end

    genvar i;
    generate
        if (PIPE_DEPTH == 0) begin
            assign input_ready  = output_ready;
            always @(*) begin
                output_valid = input_valid;
                output_data  = input_data;
            end
        end
        else if (PIPE_DEPTH > 0) begin

// We strip out first iteration of Skid Buffer instantiations to avoid having
// to refer to index -1 in the generate loop, and also to connect to the input
// handshake ports rather than the output of a previous Skid Buffer.

            wire                  valid_pipe [PIPE_DEPTH-1:0];
            wire                  ready_pipe [PIPE_DEPTH-1:0];
            wire [WORD_WIDTH-1:0] data_pipe  [PIPE_DEPTH-1:0];

            Pipeline_Skid_Buffer
            #(
                .WORD_WIDTH     (WORD_WIDTH)
            )
            input_stage
            (
                .clock          (clock),
                .clear          (clear),

                .input_valid    (input_valid),
                .input_ready    (input_ready),
                .input_data     (input_data),

                .output_valid   (valid_pipe[0]),
                .output_ready   (ready_pipe[0]),
                .output_data    (data_pipe [0])
            );

// Now repeat over the remainder of the pipeline stages, starting at stage 1,
// connecting each pipeline stage to the output of the previous pipeline
// stage.

            for (i=1; i < PIPE_DEPTH; i=i+1) begin: pipe_stages
                Pipeline_Skid_Buffer
                #(
                    .WORD_WIDTH     (WORD_WIDTH)
                )
                pipe_stage
                (
                    .clock          (clock),
                    .clear          (clear),

                    .input_valid    (valid_pipe[i-1]),
                    .input_ready    (ready_pipe[i-1]),
                    .input_data     (data_pipe [i-1]),

                    .output_valid   (valid_pipe[i]),
                    .output_ready   (ready_pipe[i]),
                    .output_data    (data_pipe [i])
                );
            end

// And finally, connect the output handshake ports of the last Skid Buffer to
// the module output handshake ports.

            assign ready_pipe [PIPE_DEPTH-1] = output_ready;
            always @(*) begin
                output_valid = valid_pipe[PIPE_DEPTH-1];
                output_data  = data_pipe [PIPE_DEPTH-1];
            end
        end
    endgenerate

endmodule

