
//# One-Hot Demultiplexer

// Connects the `word_in` input port to one of the words in the `words_out`
// output port, as selected by the `selectors` one-hot vector, and raises the
// corresponding valid bit in the `valids_out` output port.  *If more than one
// bit is set in the `selectors` input, then all the corresponding output
// words will get the input word value.*

//## Implementation Options

// Set the `BROADCAST` parameter to 1 to simply replicate and connect
// `word_in` to each word in `words_out`, without any logic. The valid bit
// will indicate which downstream logic should accept the data, and other
// logic can snoop the data if that's part of your larger design.

// Set the `BROADCAST` parameter to 0 to send `word_in` to *only* the selected
// word in `words_out`, whose valid bit is set. All other output words are
// annulled to zero. If no valid bit is set, all output words stay at zero.

// Not broadcasting the input to the output costs some logic, but less than it
// appears from a standalone synthesis of the demultiplexer: the inferred
// [Annullers](./Annuller.html) will very likely disappear into downstream LUT
// logic, it also makes tracing a simulation easier, and adds some design
// security and robustness since unselected downstream logic cannot snoop or
// accidentally receive other data.

// If necessary, select the Annuller `IMPLEMENTATION` which yields the best
// logic synthesis. Usually, this does not matter, and can be set to "AND".

// Setting `BROADCAST` to any value other than 1 or 0 will disconnect
// `word_in` from `words_out`, raise some critical warnings in your CAD tool,
// and generally cause a lot of downstream logic to optimize away, so you
// should notice...

module Demultiplexer_One_Hot
#(
    parameter       BROADCAST           = 0,
    parameter       WORD_WIDTH          = 0,
    parameter       OUTPUT_COUNT        = 0,
    parameter       IMPLEMENTATION      = "AND",

    // Do not set at instantiation
    parameter   TOTAL_WIDTH = WORD_WIDTH * OUTPUT_COUNT
)
(
    input   wire    [OUTPUT_COUNT-1:0]  selectors,
    input   wire    [WORD_WIDTH-1:0]    word_in,
    output  reg     [TOTAL_WIDTH-1:0]   words_out,
    output  reg     [OUTPUT_COUNT-1:0]  valids_out
);

    localparam OUTPUT_ZERO = {OUTPUT_COUNT{1'b0}};
    localparam TOTAL_ZERO  = {TOTAL_WIDTH{1'b0}};

    initial begin
        words_out  = TOTAL_ZERO;
        valids_out = OUTPUT_ZERO;
    end

// Pass along the selector to the downstream logic, so we know which output
// word is the selected one.

    always @(*) begin
        valids_out = selectors;
    end

// If we are *not* broadcasting, then for each output word, annul the output
// if its selector bit is not set.  Thus, only the selected output word will
// have the `word_in` data. All others will stay at zero.  Otherwise, simply
// replicate and connect the input to all outputs. 

    generate
        if (BROADCAST == 0) begin
            wire [TOTAL_WIDTH-1:0] words_out_internal;

            genvar i;
            for (i=0; i < OUTPUT_COUNT; i=i+1) begin: per_output
                Annuller
                #(
                    .WORD_WIDTH     (WORD_WIDTH),
                    .IMPLEMENTATION (IMPLEMENTATION)
                )
                output_gate
                (
                    .annul          (selectors[i] == 1'b0),
                    .data_in        (word_in),
                    .data_out       (words_out_internal[WORD_WIDTH*i +: WORD_WIDTH])
                );
            end

            always @(*) begin
                words_out = words_out_internal;
            end
        end
        else
        if (BROADCAST == 1) begin
            always @(*) begin
                words_out = {OUTPUT_COUNT{word_in}};
            end
        end
    endgenerate

endmodule

