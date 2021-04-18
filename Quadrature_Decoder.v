
//# Quadrature Decoder

// Decodes a pair of digital signals in quadrature (offset by 90deg), which
// express the direction of motion. Outputs three sets of pulses: `step`,
// `direction`, and `error`. The signals are valid when `step` is high, unless
// `error` is also high.

// This is an alternate implementation which does not use an FSM, but instead
// detects edges and distinguishes direction based on the state of the other
// signals at the time.

// The `clock` may run at any speed, so long as it can properly sample `A` and
// `B`, thus the minimum clock speed is 2x the input toggle rate.

//## Theory of Operation

// A quadrature waveform has two signals, A and B, one always 90deg out of
// phase with the other. If A leads B, when the edges of A arrive before the
// edges of B, then we define that as forward motion. If B leads A, we define
// that as backwards motion. Each edge indicates a step has been taken. If
// there are no edges, there is no motion. *Edges **never** happen at the same
// time, which is an error condition.*

// If A and B are external signals, they **must** first be synchronized to the
// clock and debounced, if generated mechanically, using
// a [Debouncer](./Debouncer_Low_Latency.html). Any two edges must arrive at
// least one clock cycle apart, else they happen at the same time, which is
// an error condition.

// The following waveform diagram shows 6 steps of forward motion, followed by
// a brief pause and 7 steps of backwards motion. Each of the edges in a cycle
// of A and B, in each direction, are labelled in sequence, starting with the
// first rising edge of each cycle in each direction.

//        F0  F2              B1  B3
//         ---     -------     ---
//     A _|   |___|       |___|   |___
//
//          F1  F3          B0  B2
//           ---     ---     ---     ---
//     B ___|   |___|   |___|   |___|

//## Stuck-At Faults

// Note that there is one error condition that cannot be detected directly: if
// either the A or B input gets stuck, the other input will keep toggling and
// generate alternating forward and backward edges. This cannot be
// disinguished from a change in direction, as shown in the middle of the
// diagram, where A is constant while B still has edges.

// Detecting this kind of error must be done at a higher level, such as
// sending a command to move in a certain direction, but not seeing that
// motion on the quadrature inputs, either because the device is physically
// stuck and no edges are seen, or only one set of edges are seen, decoding as
// minimal back-and-forth movement. The frequency of the edges would report
// the speed of motion at least, confirming that motion is happening and that
// a quadrature signal is stuck.

//## Ports, Parameters, and Constants

`default_nettype none

module Quadrature_Decoder
(
    input   wire    clock,
    input   wire    A,          // Leading A means forward
    input   wire    B,          // Leading B means backwards
    output  reg     step,       // Outputs valid while high
    output  reg     direction,  // 0/1 -> backwards/forwards
    output  reg     error       // Overrides step
);

// There are 4 possible forward or backward edges within the combined
// cycles of A and B.

    localparam EDGE_COUNT = 4;
    localparam EDGES_ZERO = {EDGE_COUNT{1'b0}};

    initial begin
        step        = 1'b0;
        direction   = 1'b0;
        error       = 1'b0;
    end

//### Positive and Negative Edges on A

    wire A_posedge;
    wire A_negedge;

    Pulse_Generator
    A_rising
    (
        .clock              (clock),
        .level_in           (A),
        .pulse_posedge_out  (A_posedge),
        // verilator lint_off PINCONNECTEMPTY
        .pulse_negedge_out  (),
        .pulse_anyedge_out  ()
        // verilator lint_off PINCONNECTEMPTY
    );

    Pulse_Generator
    A_falling
    (
        .clock              (clock),
        .level_in           (A),
        .pulse_negedge_out  (A_negedge),
        // verilator lint_off PINCONNECTEMPTY
        .pulse_posedge_out  (),
        .pulse_anyedge_out  ()
        // verilator lint_off PINCONNECTEMPTY
    );

//## Positive and Negative Edges on B

    wire B_posedge;
    wire B_negedge;

    Pulse_Generator
    B_rising
    (
        .clock              (clock),
        .level_in           (A),
        .pulse_posedge_out  (B_posedge),
        // verilator lint_off PINCONNECTEMPTY
        .pulse_negedge_out  (),
        .pulse_anyedge_out  ()
        // verilator lint_off PINCONNECTEMPTY
    );

    Pulse_Generator
    B_falling
    (
        .clock              (clock),
        .level_in           (A),
        .pulse_negedge_out  (B_negedge),
        // verilator lint_off PINCONNECTEMPTY
        .pulse_posedge_out  (),
        .pulse_anyedge_out  ()
        // verilator lint_off PINCONNECTEMPTY
    );

//## Forward and Backward Edges

// There are 4 possible forward and backward edges, defined by when one
// signal has a positive or negative edge, and the state of the other
// signal at that time.  See the waveform diagram above for reference.

    reg [EDGE_COUNT-1:0] forward_edges  = EDGES_ZERO;
    reg [EDGE_COUNT-1:0] backward_edges = EDGES_ZERO;

    always @(*) begin
        forward_edges[0]  = (A_posedge == 1'b1) && (B == 1'b0);
        forward_edges[1]  = (B_posedge == 1'b1) && (A == 1'b1);
        forward_edges[2]  = (A_negedge == 1'b1) && (B == 1'b1);
        forward_edges[3]  = (B_negedge == 1'b1) && (A == 1'b0);

        backward_edges[0] = (B_posedge == 1'b1) && (A == 1'b0);
        backward_edges[1] = (A_posedge == 1'b1) && (B == 1'b1);
        backward_edges[2] = (B_negedge == 1'b1) && (A == 1'b1);
        backward_edges[3] = (A_negedge == 1'b1) && (B == 1'b0);
    end

//## Forward and Backward Steps

// Let's reduce the edges from each direction to one signal which tells us
// if a step has been taken either forward or backward. Since no two edges
// can happen at the same time during normal operation, these two signals
// can never be active at the same time, which is a very useful
// property...

    reg forward_step  = 1'b0;
    reg backward_step = 1'b0;

    always @(*) begin
        forward_step  = (forward_edges  != EDGES_ZERO);
        backward_step = (backward_edges != EDGES_ZERO);
    end

//## Decoded Outputs

// The `step` signal goes high whenever there is a forward or backward step.

// The `direction` signal is high for a forward step, and low for
// a backward step, so we only need to use the forward step since they are
// mutually exclusive, as shown above.

// Finally, if both a forward and backward step happen at the same time,
// this is impossible, and `error` is pulsed high. The direction output
// will signal forward, but it is unknown if it is correct. The step
// output will signal a step, but it is unknown if one or more steps have
// occured.

    always @(*) begin
        step        = (forward_step == 1'b1) || (backward_step == 1'b1);
        direction   = (forward_step == 1'b1);
        error       = (forward_step == 1'b1) && (backward_step == 1'b1);
    end

endmodule

