
//# A Binary Up/Down Counter

// This counter counts by the `INCREMENT` parameter value, up or down, when
// `run` is high.  Set `up_down` to 0 to count up, or to 1 to count down.
// Load overrides counting, so you can load a `load_count` value even if `run`
// is low.  `clear` puts the counter back at INITIAL_COUNT.  The counter will
// wrap around if it goes below zero or above `(2^WORD_WIDTH)-1` and set
// `overflow` for that cycle.

// The `INCREMENT` parameter allows you to deal with situations where, for
// example, you need to count the number of bytes transferred, but your
// interface transfers multiple bytes per cycle.

// When chaining counters, which may happen if you are counting in unusual
// bases where each digit has its own counter, AND the `carry_out` of the
// previous counter with the signal fed to the `run` input of the next
// counter. The `carry_in` is kept for generality, as are the `carries` into
// each bit.

`default_nettype none

module Counter_Binary
#(
    parameter                   WORD_WIDTH      = 0,
    parameter [WORD_WIDTH-1:0]  INCREMENT       = 0,
    parameter [WORD_WIDTH-1:0]  INITIAL_COUNT   = 0
)
(
    input   wire                        clock,
    input   wire                        clear,

    input   wire                        up_down, // 0/1 --> up/down
    input   wire                        run,

    input   wire                        load,
    input   wire    [WORD_WIDTH-1:0]    load_count,

    input   wire                        carry_in,
    output  wire                        carry_out,
    output  wire    [WORD_WIDTH-1:0]    carries,
    output  wire                        overflow,

    output  wire    [WORD_WIDTH-1:0]    count
);

    localparam WORD_ZERO = {WORD_WIDTH{1'b0}};

// First we calculate the next counter value using a [Binary
// Adder/Subtractor](./Adder_Subtractor_Binary.html). Having a dedicated
// module for this allows us to change how the counter works (e.g.: BCD or
// other counting schemes) without altering any other logic. It also hides the
// tricks needed for correct arithmetic logic inference.

    wire [WORD_WIDTH-1:0] incremented_count;
    wire                  carry_out_internal;
    wire [WORD_WIDTH-1:0] carries_internal;
    wire                  overflow_internal;

    Adder_Subtractor_Binary
    #(
        .WORD_WIDTH (WORD_WIDTH)
    )
    calc_next_count
    (
        .add_sub    (up_down), // 0/1 -> A+B/A-B
        .carry_in   (carry_in),
        .A          (count),
        .B          (INCREMENT),
        .sum        (incremented_count),
        .carry_out  (carry_out_internal),
        .carries    (carries_internal),
        .overflow   (overflow_internal)
    );

// Then calculate which value to load into the counter, and when.

    reg [WORD_WIDTH-1:0]    next_count      = WORD_ZERO;
    reg                     load_counter    = 0;
    reg                     clear_counter   = 0;
    reg                     load_flags      = 0;
    reg                     clear_flags     = 0;

    always @(*) begin
        next_count      = (load  == 1'b1) ? load_count : incremented_count;
        load_counter    = (run   == 1'b1) || (load == 1'b1);
        clear_counter   = (clear == 1'b1);
        load_flags      = (run   == 1'b1);
        clear_flags     = (load  == 1'b1) || (clear == 1'b1);
    end

// Finally, store the next count value and flags, using a [Register](./Register.html).

    Register
    #(
        .WORD_WIDTH     (WORD_WIDTH),
        .RESET_VALUE    (INITIAL_COUNT)
    )
    count_storage
    (
        .clock          (clock),
        .clock_enable   (load_counter),
        .clear          (clear_counter),
        .data_in        (next_count),
        .data_out       (count)
    );

    Register
    #(
        .WORD_WIDTH     (WORD_WIDTH),
        .RESET_VALUE    (WORD_ZERO)
    )
    carries_storage
    (
        .clock          (clock),
        .clock_enable   (load_flags),
        .clear          (clear_flags),
        .data_in        (carries_internal),
        .data_out       (carries)
    );

    Register
    #(
        .WORD_WIDTH     (1),
        .RESET_VALUE    (1'b0)
    )
    carry_out_storage
    (
        .clock          (clock),
        .clock_enable   (load_flags),
        .clear          (clear_flags),
        .data_in        (carry_out_internal),
        .data_out       (carry_out)
    );

    Register
    #(
        .WORD_WIDTH     (1),
        .RESET_VALUE    (1'b0)
    )
    overflow_storage
    (
        .clock          (clock),
        .clock_enable   (load_flags),
        .clear          (clear_flags),
        .data_in        (overflow_internal),
        .data_out       (overflow)
    );

endmodule

