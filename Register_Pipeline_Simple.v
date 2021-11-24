
//# Register Pipeline (Simple)

// Pipelines data words through a number of register stages. Common uses
// include pipeline alignment, and pipelining inputs so the registers can
// retime forward into logic to allow a faster clock.

// This module is a simplification of the [Register
// Pipeline](./Register_Pipeline.html), which allows parallel input/output and
// initial values other than zero, but does not support a `PIPE_DEPTH` of
// zero like this one.

// Each cycle `clock_enable` is high, the pipeline shifts by one from
// `pipe_in` towards `pipe_out`. `clear` sets all registers to zero. If
// `PIPE_DEPTH` is zero, `pipe_in` becomes directly wired to `pipe_out` and no
// logic is inferred.

`default_nettype none

module Register_Pipeline_Simple
#(
    parameter WORD_WIDTH =  0,
    parameter PIPE_DEPTH = -1
)
(
    // If PIPE_DEPTH is zero, these are unused
    // verilator lint_off UNUSED
    input   wire                        clock,
    input   wire                        clock_enable,
    input   wire                        clear,
    // verilator lint_on  UNUSED
    input   wire    [WORD_WIDTH-1:0]    pipe_in,
    output  reg     [WORD_WIDTH-1:0]    pipe_out
);

    localparam WORD_ZERO = {WORD_WIDTH{1'b0}};

    initial begin
        pipe_out = WORD_ZERO;
    end

    genvar i;
    generate
        if (PIPE_DEPTH == 0) begin
            always @(*) begin
                pipe_out = pipe_in;
            end
        end
        else if (PIPE_DEPTH > 0) begin

// We strip out first iteration of Register instantiations to avoid having to
// refer to index -1 in the generate loop, and also to connect to `pipe_in`
// rather than the output of a previous register.

            wire [WORD_WIDTH-1:0] pipe [PIPE_DEPTH-1:0];

            Register
            #(
                .WORD_WIDTH     (WORD_WIDTH),
                .RESET_VALUE    (WORD_ZERO)
            )
            input_stage
            (
                .clock          (clock),
                .clock_enable   (clock_enable),
                .clear          (clear),
                .data_in        (pipe_in),
                .data_out       (pipe[0])
            );

// Now repeat over the remainder of the pipeline stages, starting at stage 1,
// connecting each pipeline stage to the output of the previous pipeline
// stage.

            for (i=1; i < PIPE_DEPTH; i=i+1) begin: pipe_stages
                Register
                #(
                    .WORD_WIDTH     (WORD_WIDTH),
                    .RESET_VALUE    (WORD_ZERO)
                )
                pipe_stage
                (
                    .clock          (clock),
                    .clock_enable   (clock_enable),
                    .clear          (clear),
                    .data_in        (pipe[i-1]),
                    .data_out       (pipe[i])
                );
            end

// And finally, connect the output of the last register to the module pipe output.

            always @(*) begin
                pipe_out = pipe[PIPE_DEPTH-1];
            end
        end
    endgenerate

endmodule

