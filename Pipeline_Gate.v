
//# Pipeline Gate

// Conditionally blocks ready/valid handshakes and data from passing through
// a pipeline. Handshakes complete only when the `enable` input is high.
// There is no buffering: this is purely combinational. The `enable` input
// MUST be changed synchronously to the clock.

// It is not enough to block only valid or ready: if valid is blocked, then
// the sender can still see the receiver's ready and complete a handshake,
// dropping that data. The opposite happens when blocking only ready, with the
// receiver taking in stale data or garbage.

// An example use case for a gate is to prevent a FIFO from sending out data
// while you are loading it with some unit composed of many words (e.g.
// a packet). 

//## Configuration

// If the `GATE_DATA` parameter is non-zero, a disabled gate will not let any
// data through and zero it out.  Else the data is always a simple
// pass-through, and only the ready/valid handshakes are gated. Change the
// [Annuller](./Annuller.html) `IMPLEMENTATION` as necessary, but the default
// should be fine.

`default_nettype none

module Pipeline_Gate
#(
    parameter WORD_WIDTH        = 0,
    parameter IMPLEMENTATION    = "AND",
    parameter GATE_DATA         = 0
)
(
    input   wire                        enable,

    output  wire                        input_ready,
    input   wire                        input_valid,
    input   wire    [WORD_WIDTH-1:0]    input_data,

    output  wire                        output_valid,
    input   wire                        output_ready,
    output  wire    [WORD_WIDTH-1:0]    output_data
);

    generate

        if (GATE_DATA != 0) begin : gen_gate_data

            Annuller
            #(
                .WORD_WIDTH     (WORD_WIDTH + 1 + 1),
                .IMPLEMENTATION (IMPLEMENTATION)
            )
            gate_control_and_data
            (
                .annul      (enable == 1'b0),
                .data_in    ({input_data,  output_ready, input_valid}),
                .data_out   ({output_data, input_ready,  output_valid})
            );

        end
        else begin : gen_pass_data

            assign output_data = input_data;

            Annuller
            #(
                .WORD_WIDTH     (1 + 1),
                .IMPLEMENTATION (IMPLEMENTATION)
            )
            gate_control_only
            (
                .annul      (enable == 1'b0),
                .data_in    ({output_ready, input_valid}),
                .data_out   ({input_ready,  output_valid})
            );

        end

    endgenerate

endmodule
 
