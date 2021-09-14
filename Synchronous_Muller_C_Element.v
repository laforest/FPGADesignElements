//# Synchronous Muller C-Element

// This is a synchronous (clocked) version of the Muller C-Element, which
// implements a *rendez-vous* or *join* function: the output remains low until
// all inputs go high, then the output remains high until all inputs have gone
// back low.

// The minimum `PIPE_DEPTH` is 1. Increase it as necessary to meet timing
// if you have a large number of inputs.

// Bringing `clock_enable` low will freeze the operation of the C-Element
// until brought back high. Inputs may change during that time, but they will
// not be registered, and the pipeline contents remain unchanged. Raising
// `clear` will empty the internal pipeline and bring the output low.

//## Uses

// * A chain of C-Elements can act as the control path for a Muller pipeline,
// which automatically pushes items forward as space allows. (This is
// a classic design in asychronous logic literature.)
// * A C-Element can act as a barrier to synchronize independent calculations:
// all calculations reaching a given point can signal the C-Element and stop
// until the C-Element output goes high, then continue calculating and halt
// again if they reach the same point while the C-Element output is still high,
// then signal it again once the output goes low.  A [Pulse
// Generator](./Pulse_Generator.html) and [Pulse Latch](./Pulse_Latch.html)
// would be handy here to handle the state transitions.

`default_nettype none

module Synchronous_Muller_C_Element
#(
    parameter INPUT_COUNT   = 0,
    parameter PIPE_DEPTH    = 0     // Minimum of 1
)
(
    input   wire                        clock,
    input   wire                        clear,
    input   wire                        clock_enable,

    input   wire    [INPUT_COUNT-1:0]   lines_in,
    output  reg                         line_out
);

    localparam INPUT_ZERO   = {INPUT_COUNT{1'b0}};
    localparam INPUT_ONES   = {INPUT_COUNT{1'b1}};

    localparam PIPE_WIDTH   = INPUT_COUNT + 1;
    localparam PIPE_ZERO    = {(PIPE_WIDTH * PIPE_DEPTH){1'b0}};

    initial begin
        line_out = 1'b0;
    end

// Pipeline all the inputs and the combinational output together. This enables
// forward retiming for performance, and stores the output state (which is
// what makes this version synchronous). At a `PIPE_DEPTH` of 1, this behaves
// identically to having a single output register, except it can retime inside
// the feedback loop from the `line_out`.

    wire [INPUT_COUNT-1:0]  lines_in_pipelined;
    wire                    line_out_pipelined;

    Register_Pipeline
    #(
        .WORD_WIDTH (PIPE_WIDTH),
        .PIPE_DEPTH (PIPE_DEPTH),
        // concatenation of each stage initial/reset value
        .RESET_VALUES   (PIPE_ZERO)
    )
    input_pipeline
    (
        .clock          (clock),
        .clock_enable   (clock_enable),
        .clear          (clear),
        .parallel_load  (1'b0),
        .parallel_in    (PIPE_ZERO),
        // verilator lint_off PINCONNECTEMPTY
        .parallel_out   (),
        // verilator lint_on  PINCONNECTEMPTY
        .pipe_in        ({lines_in,             line_out}),
        .pipe_out       ({lines_in_pipelined,   line_out_pipelined})
    );

// And compute the set and hold functions based off the pipelined values.

    reg set_output  = 1'b0;
    reg hold_output = 1'b0;

    always @(*) begin
        set_output  = (lines_in_pipelined == INPUT_ONES);
        hold_output = (lines_in_pipelined != INPUT_ZERO) && (line_out_pipelined == 1'b1);
        line_out    = (set_output         == 1'b1)       || (hold_output        == 1'b1);
    end

endmodule

