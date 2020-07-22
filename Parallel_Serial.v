
//# Parallel to Serial Converter

// Reads in a data word, sends it out serially, bit by bit (MSB first), and
// signals when the final bit is out and a new data word can be read-in, in
// the same cycle if necessary to create an uninterrupted serial stream.

// When the `parallel_in` ready/valid handshakes completes, `parallel_in` is
// loaded, `parallel_in_ready` goes low while the bits shift out (MSB first),
// and goes back high once the last loaded bit appears at `serial_out`,
// allowing a simultanous reload for a continuous stream of serial bits to be
// sent.

// Otherwise, if no new word is loaded, the shifter halts (holding the last
// bit steady at `serial_out`, and `parallel_in_ready` goes high, awaiting the
// next load.

// Holding `clock_enable` low halts any shifting, holding all bits in place
// and ignoring any changes at the control and data inputs, *except for
// `clear`*.

// Asserting `clear` will empty the shift register, zero-out the counter,
// raise `parallel_in_ready`, and halt all activity until the next ready/valid
// handshake.

`default_nettype none

module Parallel_Serial
#(
    parameter WORD_WIDTH = 0
)
(
    input   wire                        clock,
    input   wire                        clock_enable,
    input   wire                        clear,

    input   wire                        parallel_in_valid,
    output  reg                         parallel_in_ready,
    input   wire    [WORD_WIDTH-1:0]    parallel_in,

    output  wire                        serial_out
);

    `include "clog2_function.vh"

    localparam WORD_ZERO   = {WORD_WIDTH{1'b0}};
    localparam COUNT_WIDTH = clog2(WORD_WIDTH);
    localparam COUNT_ZERO  = {COUNT_WIDTH{1'b0}};
    localparam COUNT_BITS  = WORD_WIDTH - 1; 

    initial begin
        parallel_in_ready = 1'b1; // We start empty, so ready to load.
    end

// Count the number of bit shifts remaning, starting at WORD_WIDTH-1 since the
// first bit is immediately visible at `serial_out` after a load.  When the
// last bit is visible at `serial_out`, the count reaches zero, the counter
// halts, and we can immediately load a new word.

    reg                     counter_run  = 1'b0;
    reg                     counter_load = 1'b0;
    wire [COUNT_WIDTH-1:0]  count;

    Counter_Binary
    #(
        .WORD_WIDTH     (COUNT_WIDTH),
        .INCREMENT      (1),
        .INITIAL_COUNT  (COUNT_ZERO)
    )
    shifts_remaining
    (
        .clock          (clock),
        .clear          (clear),
        .up_down        (1'b1), // 0 up, 1 down
        .run            (counter_run),
        .load           (counter_load),
        .load_count     (COUNT_BITS [COUNT_WIDTH-1:0]),
        .carry_in       (1'b0),
        // verilator lint_off PINCONNECTEMPTY
        .carry_out      (),
        // verilator lint_on  PINCONNECTEMPTY
        .count          (count)
    );

// The shift register only shifts when the counter is running.

    reg shifter_run  = 1'b0;
    reg shifter_load = 1'b0;

    Register_Pipeline
    #(
        .WORD_WIDTH     (1),
        .PIPE_DEPTH     (WORD_WIDTH),
        .RESET_VALUES   (WORD_ZERO)
    )
    shift_register
    (
        .clock          (clock),
        .clock_enable   (shifter_run),
        .clear          (clear),
        .parallel_load  (shifter_load),
        .parallel_in    (parallel_in),
        // verilator lint_off PINCONNECTEMPTY
        .parallel_out   (),
        // verilator lint_on  PINCONNECTEMPTY
        .pipe_in        (1'b0),
        .pipe_out       (serial_out)
    );

// Completing the parallel input handshake both loads the data word into the
// shift register and loads the counter with the pipeline depth (minus 1),
// starting the bit shifting.  After all the bits have appeared at
// `serial_out`, the counter reaches to zero, halts, and raises
// `parallel_in_ready`.

    reg handshake_done = 1'b0;

    always @(*) begin
        parallel_in_ready   = (count == COUNT_ZERO) && (clock_enable == 1'b1);
        handshake_done      = (parallel_in_valid == 1'b1) && (parallel_in_ready == 1'b1);

        counter_run         = (count != COUNT_ZERO) && (clock_enable == 1'b1);
        counter_load        = (handshake_done == 1'b1);

        shifter_run         = (counter_run == 1'b1) || (counter_load == 1'b1);
        shifter_load        = (counter_load == 1'b1);
    end

endmodule

