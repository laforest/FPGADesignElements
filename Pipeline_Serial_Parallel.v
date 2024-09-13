
//# Pipeline Serial to Parallel Converter

// Reads in multiple serial words (most-significant word first) and signals
// when the last input word has been read-in and a new, wider output word is
// ready to be read-out, in the same cycle if necessary to receive an
// uninterrupted serial stream.

// Holding `clock_enable` low halts any shifting, holding all bits in place
// and ignoring any changes at the control and data inputs, *except for
// `clear`*.

// Asserting `clear` will empty the shift register, re-initialize the counter,
// drop `parallel_out_valid`, and start shifting-in serial words.

// This is a generalization of the simpler [Serial to Parallel Converter](./Serial_Parallel.html).

`default_nettype none

module Pipeline_Serial_Parallel
#(
    parameter WORD_WIDTH_IN     = 0,
    parameter WORD_COUNT_IN     = 0,

    // Do not set at instantiation, except in Vivado IPI
    parameter WORD_WIDTH_OUT    = WORD_WIDTH_IN * WORD_COUNT_IN
)
(
    input   wire                            clock,
    input   wire                            clock_enable,
    input   wire                            clear,

    input   wire                            serial_in_valid,
    output  reg                             serial_in_ready,
    input   wire    [WORD_WIDTH_IN-1:0]     serial_in,

    output  reg                             parallel_out_valid,
    input   wire                            parallel_out_ready,
    output  wire    [WORD_WIDTH_OUT-1:0]    parallel_out
);

    `include "clog2_function.vh"

    localparam WORD_ZERO_IN     = {WORD_WIDTH_IN{1'b0}};
    localparam WORD_ZERO_OUT    = {WORD_COUNT_IN{WORD_ZERO_IN}};
    localparam COUNT_WIDTH      = clog2(WORD_COUNT_IN) + 1;   // Since we must be able to index 0 to N, not N-1
    localparam COUNT_ZERO       = {COUNT_WIDTH{1'b0}};

    initial begin
        parallel_out_valid  = 1'b0; // We start empty, so ready to shift-in.
        serial_in_ready     = 1'b1;
    end

// Count the number of word shifts remaining. When the last word has been
// read-in from `serial_in`, the count reaches zero, the counter halts, and we
// can immediately read out the word.

// As the initial output word is read out, we reload the counter with the
// initial value if there is no concurrent serial input, or with one less than
// the initial value if there is a concurrent serial input.

    reg                     counter_run         = 1'b0;
    reg                     counter_load        = 1'b0;
    reg  [COUNT_WIDTH-1:0]  counter_load_value  = COUNT_ZERO;
    wire [COUNT_WIDTH-1:0]  count;

    Counter_Binary
    #(
        .WORD_WIDTH     (COUNT_WIDTH),
        .INCREMENT      (1),
        .INITIAL_COUNT  (WORD_COUNT_IN [COUNT_WIDTH-1:0])
    )
    shifts_remaining
    (
        .clock          (clock),
        .clear          (clear),
        .up_down        (1'b1), // 0 up, 1 down
        .run            (counter_run),
        .load           (counter_load),
        .load_count     (counter_load_value [COUNT_WIDTH-1:0]),
        .carry_in       (1'b0),
        // verilator lint_off PINCONNECTEMPTY
        .carry_out      (),
        .carries        (),
        .overflow       (),
        // verilator lint_on  PINCONNECTEMPTY
        .count          (count)
    );

// The shift register only shifts when the counter is running.

    reg shifter_run  = 1'b0;

    Register_Pipeline
    #(
        .WORD_WIDTH     (WORD_WIDTH_IN),
        .PIPE_DEPTH     (WORD_COUNT_IN),
        .RESET_VALUES   (WORD_ZERO_OUT)
    )
    shift_register
    (
        .clock          (clock),
        .clock_enable   (shifter_run),
        .clear          (clear),
        .parallel_load  (1'b0),
        .parallel_in    (WORD_ZERO_OUT),
        .parallel_out   (parallel_out),
        .pipe_in        (serial_in),
        // verilator lint_off PINCONNECTEMPTY
        .pipe_out       ()
        // verilator lint_on  PINCONNECTEMPTY
    );

// Completing the parallel output handshake reloads the counter, starting the
// word shifting.  After all the words have been read-in from `serial_in`, the
// counter reaches to zero, halts, and raises `parallel_out_valid`.

    reg output_handshake_done   = 1'b0;
    reg input_handshake_done    = 1'b0;

    always @(*) begin
        output_handshake_done   = (parallel_out_valid == 1'b1) && (parallel_out_ready == 1'b1);
        input_handshake_done    = (serial_in_valid    == 1'b1) && (serial_in_ready    == 1'b1);
    end

    always @(*) begin
        parallel_out_valid      =  (count == COUNT_ZERO)                                     && (clock_enable == 1'b1);
        serial_in_ready         = ((count != COUNT_ZERO) || (output_handshake_done == 1'b1)) && (clock_enable == 1'b1);

        counter_run             =  (count != COUNT_ZERO) && (input_handshake_done  == 1'b1)  && (clock_enable == 1'b1);
        counter_load            = (output_handshake_done == 1'b1);

        shifter_run             = (counter_run == 1'b1) || (counter_load == 1'b1);

        counter_load_value      = ((output_handshake_done == 1'b1) && (input_handshake_done == 1'b1)) ? WORD_COUNT_IN - 1 : WORD_COUNT_IN;
    end

endmodule

