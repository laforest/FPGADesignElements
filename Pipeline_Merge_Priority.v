
//# Pipeline Merge (Priority Arbitration)

// Takes in multiple input ready/valid handshakes with associated data, and
// merges them one at a time into a single output ready/valid handshake. The
// inputs are merged by priority, with the lowest indexed input having
// the highest priority.

//## Atomicity

// So long as an input has the highest priority valid signal asserted, it's
// data will be passed to the output. Backpressure still works via the ready
// signal. *However, if at any time a higher-priority valid signal is raised,
// it will take over the output.* No data will be lost, but sources will be
// interleaved at the output.  Thus, if you can't avoid interleaving, attach
// some metadata in parallel to the data (e.g.: a source ID number) to allow
// sorting it out further down the pipeline.

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

module Pipeline_Merge_Priority
#(
    parameter WORD_WIDTH     = 0,
    parameter INPUT_COUNT    = 0,
    parameter IMPLEMENTATION = "AND",

    // Do not set at instantiation, except in IPI
    parameter TOTAL_WIDTH   = WORD_WIDTH * INPUT_COUNT
)
(
    input  wire                     clock,
    input  wire                     clear,

    input  wire [INPUT_COUNT-1:0]   input_valid,
    output wire [INPUT_COUNT-1:0]   input_ready,
    input  wire [TOTAL_WIDTH-1:0]   input_data,

    output reg                      output_valid,
    input  wire                     output_ready,
    output wire [WORD_WIDTH-1:0]    output_data
);

    localparam INPUT_ZERO = {INPUT_COUNT{1'b0}};

    initial begin
        output_valid = 1'b0;
    end

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

// If any input is valid, then pass it to the output valid port.

    always @(*) begin
        output_valid = (input_valid_buffered != INPUT_ZERO);
    end

// Then filter the input valid signals to only one, in order of priority.
// Least-significant bit has highest priority.

    wire [INPUT_COUNT-1:0] input_valid_granted;

    Arbiter_Priority
    #(
        .INPUT_COUNT    (INPUT_COUNT)
    )
    pipeline_arbiter
    (
        .requests       (input_valid_buffered),
        .grant          (input_valid_granted)
    );

// Then use the filtered valid signal to select the data to pass to the
// output.

    Multiplexer_One_Hot
    #(
        .WORD_WIDTH     (WORD_WIDTH),
        .WORD_COUNT     (INPUT_COUNT),
        .OPERATION      ("OR"),
        .IMPLEMENTATION (IMPLEMENTATION)
    )
    data_out_mux
    (
        .selectors      (input_valid_granted),
        .words_in       (input_data_buffered),
        .word_out       (output_data)
    );

// Use the filtered valid signal to steer the selected output ready port to
// the input ready port. Since this is a single-bit signal, the valid isn't
// necessary if we don't broadcast.

    Demultiplexer_One_Hot
    #(
        .BROADCAST      (0),
        .WORD_WIDTH     (1),
        .OUTPUT_COUNT   (INPUT_COUNT),
        .IMPLEMENTATION (IMPLEMENTATION)
    )
    ready_in_demux
    (
        .selectors      (input_valid_granted),
        .word_in        (output_ready),
        .words_out      (input_ready_buffered),
        // verilator lint_off PINCONNECTEMPTY
        .valids_out     ()
        // verilator lint_on  PINCONNECTEMPTY
    );

endmodule

