
//# Binary Demultiplexer

// Connects the `word_in` input port to one of the words in the `words_out`
// output port, as selected by the `output_port_selector` binary address, and
// raises the corresponding valid bit in the `valids_out` output port.

// All unselected output ports and valid bits are set to zero, and if the
// `output_port_selector` value is greater than the number of output words,
// then *all* output words and valid bits stay at zero.  This costs some logic,
// but makes tracing a simulation easier, and adds some design security and
// robustness since unselected downstream logic cannot snoop or accidentally
// receive other data.

module Demultiplexer_Binary
#(
    parameter       WORD_WIDTH          = 0,
    parameter       ADDR_WIDTH          = 0,
    parameter       OUTPUT_COUNT        = 0,

    // Do not set at instantiation
    parameter   TOTAL_WIDTH = WORD_WIDTH * OUTPUT_COUNT
)
(
    input   wire    [ADDR_WIDTH-1:0]    output_port_selector,
    input   wire    [WORD_WIDTH-1:0]    word_in,
    output  wire    [TOTAL_WIDTH-1:0]   words_out,
    output  wire    [OUTPUT_COUNT-1:0]  valids_out
);

// Convert the binary `output_port_selector` to a single one-hot bit vector
// which signals which output port will receive the input word.

    Binary_to_One_Hot
    #(
        .BINARY_WIDTH   (ADDR_WIDTH),
        .OUTPUT_WIDTH   (OUTPUT_COUNT)
    )
    valid_out
    (
        .binary_in      (output_port_selector),
        .one_hot_out    (valids_out)
    );

// Then, for each output port, annul the output if its valid bit is not set.
// Thus, only the selected output port will have the `word_in` data. All
// others will stay at zero.

    generate
        genvar i;
        for (i=0; i < OUTPUT_COUNT; i=i+1) begin: per_output
            Annuller
            #(
                .WORD_WIDTH     (WORD_WIDTH),
                .IMPLEMENTATION ("AND")
            )
            output_gate
            (
                .annul          (valids_out[i] == 1'b0),
                .data_in        (word_in),
                .data_out       (words_out[WORD_WIDTH*i +: WORD_WIDTH])
            );
        end
    endgenerate

endmodule

