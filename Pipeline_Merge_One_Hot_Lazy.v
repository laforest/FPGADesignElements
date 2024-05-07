
//# Pipeline Merge (One-Hot Selector, Lazy)

// Takes in multiple input ready/valid handshakes with associated data, and
// merges them one at a time into a single output ready/valid handshake. An
// input is merged when selected by a one-hot bit vector. (Use [Binary to
// One-Hot](./Binary_to_One_Hot.html) if necessary.)

// This version is "lazy": there is no buffering from input to output, which
// is sometimes useful when maintaining synchronization across pipelines.
// This means the path is completely combinational.

//## Interleaving

// Normally, the `selector` remains stable while input transfers are in
// progress (input ready and valid both high), but if you are careful you can
// change the selector each cycle to interleave data from multiple inputs
// transfers into the output transfer.

//## Multiple/No selected inputs

// Normally, only one bit of the one-hot `selector` must be set at any time.

// If more than one bit is set, then the multiple selected inputs are combined
// so that the output receives a Boolean reduction of the selected input
// valids (`HANDSHAKE_MERGE`), and a possibly different Boolean reduction of
// the selected input data (`DATA_MERGE`). For example, if both merge
// parameters are set to `"OR"`, and if you can guarantee that only one input
// is active at any given moment, the resulting operation is that of
// a non-synchronizing [Pipeline Join](./Pipeline_Join.html).

// If no bit is set, then the inputs are all disconnected and no input
// handshake can complete, effectively forming a multi-input [Pipeline
// Gate](./Pipeline_Gate.html). Any pending output handshake can still
// complete.  Formally speaking, letting the output handshake proceed after an
// input handshake was accepted is necessary to not break the monotonicity
// property of Kahn Process Networks.

// The IMPLEMENTATION parameter defaults to "AND", and controls the
// implementation of the Annullers inside the mux/demux. It is unlikely you
// will need to change it.

//## Avoiding combinational loops

// As a design convention, we must avoid a combinational path between the
// valid and ready signals in a given pipeline interface, because if the other
// end of the pipeline connection also has a ready/valid combinational path,
// connecting these two interfaces will form a combinational loop, which
// cannot be analyzed for timing, or simulated reliably.

// We break this convention here and let a combinational path exist as it is
// sometimes useful to maintain synchronization across pipelines.

`default_nettype none

module Pipeline_Merge_One_Hot_Lazy
#(
    parameter WORD_WIDTH        = 0,
    parameter INPUT_COUNT       = 0,
    parameter HANDSHAKE_MERGE   = "OR",
    parameter DATA_MERGE        = "OR",
    parameter IMPLEMENTATION    = "AND",

    // Do not set at instantiation, except in IPI
    parameter TOTAL_WIDTH   = WORD_WIDTH * INPUT_COUNT
)
(
    input  wire [INPUT_COUNT-1:0]   selector,

    input  wire [INPUT_COUNT-1:0]   input_valid,
    output wire [INPUT_COUNT-1:0]   input_ready,
    input  wire [TOTAL_WIDTH-1:0]   input_data,

    output wire                     output_valid,
    input  wire                     output_ready,
    output wire [WORD_WIDTH-1:0]    output_data
);

// First, pass the selected input valid to the output valid.

    Multiplexer_One_Hot
    #(
        .WORD_WIDTH     (1),
        .WORD_COUNT     (INPUT_COUNT),
        .OPERATION      (HANDSHAKE_MERGE),
        .IMPLEMENTATION (IMPLEMENTATION)
    )
    valid_mux
    (
        .selectors  (selector),
        .words_in   (input_valid),
        .word_out   (output_valid)
    );

// Select the associated input data to pass to the output data.

    Multiplexer_One_Hot
    #(
        .WORD_WIDTH     (WORD_WIDTH),
        .WORD_COUNT     (INPUT_COUNT),
        .OPERATION      (DATA_MERGE),
        .IMPLEMENTATION (IMPLEMENTATION)
    )
    data_out_mux
    (
        .selectors      (selector),
        .words_in       (input_data),
        .word_out       (output_data)
    );

// Steer the output ready port to the selected input ready port.  Since this
// is a single-bit signal, the `valids_out` isn't necessary if we don't
// broadcast.

    Demultiplexer_One_Hot
    #(
        .BROADCAST      (0),
        .WORD_WIDTH     (1),
        .OUTPUT_COUNT   (INPUT_COUNT),
        .IMPLEMENTATION (IMPLEMENTATION)
    )
    ready_in_demux
    (
        .selectors      (selector),
        .word_in        (output_ready),
        .words_out      (input_ready),
        // verilator lint_off PINCONNECTEMPTY
        .valids_out     ()
        // verilator lint_on  PINCONNECTEMPTY
    );

endmodule

