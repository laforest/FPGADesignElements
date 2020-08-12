
//# Pipeline Merge (One-Hot Selector)

// Takes in multiple input ready/valid handshakes with associated data, and
// merges them one at a time into a single output ready/valid handshake. An
// input is merged when selected by a one-hot bit vector. (Use [Binary to
// One-Hot](./Binary_to_One_Hot.html) if necessary.)

//## Interleaving

// Normally, the `selector` remains stable while input transfers are in
// progress (input ready and valid both high), but if you are careful you can
// change the selector each cycle to interleave data from multiple inputs
// transfers into the output transfer.

//## Multiple selected inputs

// Normally, only one bit of the one-hot `selector` must be set at any time.
// If no bit is set, then the inputs and the output are all disconnected and
// no handshake can complete.  If more than one bit is set, then the multiple
// selected inputs are combined so that the output receives the OR-reduction
// of the selected input valids, and the OR-reduction of the selected input
// data. This behaviour might be usable *if you can guarantee that only one
// input is active at any given moment*, resulting in a non-synchronizing
// [Pipeline Join](./Pipeline_Join.html).

// The IMPLEMENTATION parameter defaults to "AND", and controls the
// implementation of the Annullers inside the mux/demux. It is unlikely you
// will need to change it.

//## Avoiding combinational loops

// As a design convention, we must avoid a combinational path between the
// valid and ready signals in a given pipeline interface, because if the other
// end of the pipeline connection also has a ready/valid combinational path,
// connecting these two interfaces will form a combinational loop, which
// cannot be analyzed for timing, or simulated reliably.

// Thus, the input interfaces here are buffered to break the combinational
// path, even if the buffering is redundant. It's not worth the risk of a bad
// simulation or synthesis otherwise.

`default_nettype none

module Pipeline_Merge_One_Hot
#(
    parameter WORD_WIDTH     = 32,
    parameter INPUT_COUNT    = 7,
    parameter IMPLEMENTATION = "AND",

    // Do not set at instantiation, except in IPI
    parameter TOTAL_WIDTH   = WORD_WIDTH * INPUT_COUNT
)
(
    input  wire                     clock,
    input  wire                     clear,

    input  wire [INPUT_COUNT-1:0]   selector,

    input  wire [INPUT_COUNT-1:0]   input_valid,
    output wire [INPUT_COUNT-1:0]   input_ready,
    input  wire [TOTAL_WIDTH-1:0]   input_data,

    output wire                     output_valid,
    input  wire                     output_ready,
    output wire [WORD_WIDTH-1:0]    output_data
);

// First, we must buffer the input interfaces to break the combinational path
// from valid to ready.

    wire [INPUT_COUNT-1:0]   input_valid_buffered;
    wire [INPUT_COUNT-1:0]   input_ready_buffered;
    wire [TOTAL_WIDTH-1:0]   input_data_buffered;

    generate
        genvar j;
        for(j=0; j < INPUT_COUNT; j=j+1) begin: per_input
            Pipeline_Skid_Buffer
            #(
                .WORD_WIDTH (WORD_WIDTH)
            )
            input_buffer
            (
                .clock          (clock),
                .clear          (clear),
                
                .input_valid    (input_valid[j]),
                .input_ready    (input_ready[j]),
                .input_data     (input_data [WORD_WIDTH*j +: WORD_WIDTH]),
                
                .output_valid   (input_valid_buffered[j]),
                .output_ready   (input_ready_buffered[j]),
                .output_data    (input_data_buffered [WORD_WIDTH*j +: WORD_WIDTH])
            );
        end
    endgenerate

// Pass the selected input valid to the output valid.

    Multiplexer_One_Hot
    #(
        .WORD_WIDTH     (1),
        .WORD_COUNT     (INPUT_COUNT),
        .OPERATION      ("OR"),
        .IMPLEMENTATION (IMPLEMENTATION)
    )
    valid_mux
    (
        .selectors  (selector),
        .words_in   (input_valid_buffered),
        .word_out   (output_valid)
    );

// Select the associated input data to pass to the output.

    Multiplexer_One_Hot
    #(
        .WORD_WIDTH     (WORD_WIDTH),
        .WORD_COUNT     (INPUT_COUNT),
        .OPERATION      ("OR"),
        .IMPLEMENTATION (IMPLEMENTATION)
    )
    data_out_mux
    (
        .selectors      (selector),
        .words_in       (input_data_buffered),
        .word_out       (output_data)
    );

// Finally, steer the output ready port to the selected input ready port.
// Since this is a single-bit signal, the valid isn't necessary if we don't
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
        .words_out      (input_ready_buffered),
        // verilator lint_off PINCONNECTEMPTY
        .valids_out     ()
        // verilator lint_on  PINCONNECTEMPTY
    );

endmodule

