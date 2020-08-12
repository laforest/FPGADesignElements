
//# Pipeline Branch (One-Hot)

// Takes an input ready/valid handshake, with associated data, and connects it
// to one of several output ready/valid handshake selected by a one-hot bit
// vector. (Use [Binary to One-Hot](./Binary_to_One_Hot.html) if necessary.)

//## Demultiplexing

// Normally, the `selector` remains stable while transfers are in progress
// (input ready and valid both high), but if you are careful you can change
// the selector each cycle to demultiplex the input data to multiple
// output data.

//## Multiple selected outputs

// Normally, only one bit of the one-hot `selector` must be set at any time.
// If no bit is set, then the input and the outputs are all disconnected and
// no handshake can complete.  If more than one bit is set, then the multiple
// selected outputs each get a copy of the valid signal and the associated
// data (the others get zero), and the input ready receives a Boolean
// OR-reduction of all the selected output ready signals, which sends the data
// to the first selected output which is ready, and any other outputs ready in
// the same cycle. This behaviour is like a non-synchronizing [Eager Pipeline
// Fork](./Pipeline_Fork_Eager.html).

// The IMPLEMENTATION parameter defaults to "AND", and controls the
// implementation of the Annullers inside the mux/demux. It is unlikely you
// will need to change it.

`default_nettype none

module Pipeline_Branch_One_Hot
#(
    parameter WORD_WIDTH        = 0,
    parameter OUTPUT_COUNT      = 0,
    parameter IMPLEMENTATION    = "AND",

    // Do not set at instantiation, except in IPI
    parameter TOTAL_WIDTH = WORD_WIDTH * OUTPUT_COUNT
)
(
    input  wire [OUTPUT_COUNT-1:0]  selector,

    input  wire                     input_valid,
    output wire                     input_ready,
    input  wire [WORD_WIDTH-1:0]    input_data,

    output wire [OUTPUT_COUNT-1:0]  output_valid,
    input  wire [OUTPUT_COUNT-1:0]  output_ready,
    output wire [TOTAL_WIDTH-1:0]   output_data
);

// Steer the selected output ready to the input ready.

    Multiplexer_One_Hot
    #(
        .WORD_WIDTH     (1),
        .WORD_COUNT     (OUTPUT_COUNT),
        .OPERATION      ("OR"),         // Other operations aren't meaningful here.
        .IMPLEMENTATION (IMPLEMENTATION)
    )
    ready_mux
    (
        .selectors      (selector),
        .words_in       (output_ready),
        .word_out       (input_ready)
    );

// Steer the input valid to the selected output valid.

    Demultiplexer_One_Hot
    #(
        .BROADCAST      (0),
        .WORD_WIDTH     (1),
        .OUTPUT_COUNT   (OUTPUT_COUNT),
        .IMPLEMENTATION (IMPLEMENTATION)
    )
    valid_demux
    (
        .selectors      (selector),
        .word_in        (input_valid),
        .words_out      (output_valid),
        // verilator lint_off PINCONNECTEMPTY
        .valids_out     ()
        // verilator lint_on  PINCONNECTEMPTY
    );

// Steer the input data to the selected output data.
// Other outputs get all-zero data.

    Demultiplexer_One_Hot
    #(
        .BROADCAST      (0),
        .WORD_WIDTH     (WORD_WIDTH),
        .OUTPUT_COUNT   (OUTPUT_COUNT),
        .IMPLEMENTATION (IMPLEMENTATION)
    )
    data_demux
    (
        .selectors      (selector),
        .word_in        (input_data),
        .words_out      (output_data),
        // verilator lint_off PINCONNECTEMPTY
        .valids_out     ()
        // verilator lint_on  PINCONNECTEMPTY
    );

endmodule

