
//# Pipeline Handshake Multiplier

// Accepts one ready/valid handshake at its input, along with a repeat count,
// and will not accept another input handshake until `input_data_repeat_count`
// output handshakes have been accepted.  Each output handshake is a copy of
// the input handshake, without the repeat count.

// `input_data_repeat_count` must be less or equal to `MAX_REPEAT_COUNT`.

// *Loading a repeat count of zero immediately resets the buffer, and so the
// input handshake is sunk and so no output handshakes happen, and we
// immediately are ready to accept a new input handshake.*

`default_nettype none

module Pipeline_Handshake_Multiplier
#(
    parameter WORD_WIDTH        = 0,
    parameter MAX_REPEAT_COUNT  = 0,

    // Do not set at instantiation, except in Vivado IPI.
    parameter REPEAT_COUNT_WIDTH = clog2(MAX_REPEAT_COUNT) + 1 // +1 to hold exact number, not a 0-index
)
(
    input   wire                                clock,
    input   wire                                clear,

    input   wire                                input_data_valid,
    output  wire                                input_data_ready,
    input   wire    [WORD_WIDTH-1:0]            input_data,
    input   wire    [REPEAT_COUNT_WIDTH-1:0]    input_data_repeat_count,

    output  wire                                output_data_valid,
    input   wire                                output_data_ready,
    output  wire    [WORD_WIDTH-1:0]            output_data
);

    `include "clog2_function.vh"

// First, let's buffer the input handshake.  A Half Buffer will hold its
// output steady and not accept another input handshake until its output
// handshake completes. A repeat count of zero clears the buffer immediately.

    // verilator lint_off UNOPTFLAT
    wire output_data_ready_divided;
    // verilator lint_on  UNOPTFLAT

    reg clear_input_buffer = 1'b0;

    Pipeline_Half_Buffer
    #(
        .WORD_WIDTH         (WORD_WIDTH),
        .CIRCULAR_BUFFER    (0)  // non-zero to enable
    )
    input_buffer
    (
        .clock              (clock),
        .clear              (clear | clear_input_buffer),

        .input_valid        (input_data_valid),
        .input_ready        (input_data_ready),
        .input_data         (input_data),

        .output_valid       (output_data_valid),
        .output_ready       (output_data_ready_divided),
        .output_data        (output_data)
    );

// We only need to control the buffer output ready signal and assert it once
// after `input_data_repeat_count` module output handshakes. The repeat count
// is stored in the Pulse Divider one cycle before the output handshake
// becomes ready.

    localparam REPEAT_ZERO = {REPEAT_COUNT_WIDTH{1'b0}};

    reg module_input_handshake_done  = 1'b0;
    reg module_output_handshake_done = 1'b0;

    always @(*) begin
        module_input_handshake_done  = (input_data_valid            == 1'b1) && (input_data_ready        == 1'b1);
        clear_input_buffer           = (module_input_handshake_done == 1'b1) && (input_data_repeat_count == REPEAT_ZERO);
        module_output_handshake_done = (output_data_valid           == 1'b1) && (output_data_ready       == 1'b1);
    end

// NOTE: a `input_data_repeat_count` of zero DOES get loaded, which will cause
// the Pulse_Divider to immediately load the first non-zero value it sees, but
// since the input_buffer is not asserting valid at its output, any output
// from the Pulse_Divider cannot complete any handshakes and has no effect.

    Pulse_Divider
    #(
        .WORD_WIDTH         (REPEAT_COUNT_WIDTH),
        .INITIAL_DIVISOR    (MAX_REPEAT_COUNT [REPEAT_COUNT_WIDTH-1:0])
    )
    output_handshake_counter
    (
        .clock              (clock),
        .restart            (module_input_handshake_done),
        .divisor            (input_data_repeat_count),
        .pulses_in          (module_output_handshake_done),
        .pulse_out          (output_data_ready_divided),
        // verilator lint_off PINCONNECTEMPTY
        .div_by_zero        ()
        // verilator lint_on  PINCONNECTEMPTY
    );

endmodule

