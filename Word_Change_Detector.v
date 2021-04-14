
//# Word Change Detector

// Emits a pulse when one or more bits in the input word change.

`default_nettype none

module Word_Change_Detector
#(
    parameter WORD_WIDTH = 0
)
(
    input   wire                        clock,
    input   wire    [WORD_WIDTH-1:0]    input_word,
    output  reg                         output_pulse
);

    localparam WORD_ZERO = {WORD_WIDTH{1'b0}};

    initial begin
        output_pulse = 1'b0;
    end

// Any change on each bit of the input word will raise a pulse.

    wire [WORD_WIDTH-1:0] bit_change;

    generate

        genvar i;

        for (i=0; i < WORD_WIDTH; i=i+1) begin : per_bit
            Pulse_Generator
            bit_change_detector
            (
                .clock              (clock),
                .level_in           (input_word[i]),
                .pulse_anyedge_out  (bit_change[i]),
                //verilator lint_off PINCONNECTEMPTY
                .pulse_posedge_out  (),
                .pulse_negedge_out  ()
                //verilator lint_on  PINCONNECTEMPTY
                
            );
        end

    endgenerate

// Reduce any number of pulses to one pulse.

    always @(*) begin
        output_pulse = (bit_change != WORD_ZERO);
    end

endmodule

