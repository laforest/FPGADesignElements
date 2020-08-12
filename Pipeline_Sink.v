
//# Pipeline Sink

// Acts as either a pass-through or a sink for ready/valid pipeline
// handshakes, along with the associated data.  While `sink` is raised, any
// handshake and data presented at the input is immediately lost, and the
// output never raises valid and presents all-zero data.  *All signals must be
// synchronous. There is no buffering or registering.*

// The main use of a sink is to disconnect an output of a pipeline fork or
// branch so no backpressure can come from that output. Else, an inactive
// output will stall the handshakes to all the other outputs.

// The default Annuller `IMPLEMENTATION` of "AND" should be fine. Check your
// synthesis results if necessary.

`default_nettype none

module Pipeline_Sink
#(
    parameter WORD_WIDTH        = 0,
    parameter IMPLEMENTATION    = "AND"
)
(
    input   wire                        sink,

    input   wire                        input_valid,
    output  reg                         input_ready,
    input   wire    [WORD_WIDTH-1:0]    input_data,

    output  wire                        output_valid,
    input   wire                        output_ready,
    output  wire    [WORD_WIDTH-1:0]    output_data
);

    initial begin
        input_ready = 1'b0;
    end

// Annull all forward logic (data and valid) if sunk.

    localparam FORWARD_WIDTH = WORD_WIDTH + 1;

    Annuller
    #(
        .WORD_WIDTH     (FORWARD_WIDTH),
        .IMPLEMENTATION (IMPLEMENTATION)
    )
    forward_sink
    (
        .annul          (sink),
        .data_in        ({input_data,  input_valid}),
        .data_out       ({output_data, output_valid})
    );

// Present a perpetually ready input if sunk, so no stalling can happen.

    always @(*) begin
        input_ready = (sink == 1'b1) ? 1'b1 : output_ready;
    end

endmodule

