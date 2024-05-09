
//# Pipeline Credit Gate

// Gates a pipeline if the internal credit count is zero. A separate pulse
// input adds one credit per pulse. Continuous, multi-cycles pulses are allowed.
// Each completed pipeline handshake from input to output consumes one credit.  The credit count
// is available to drive other logic (usually another [Pipeline Gate](./Pipeline_Gate.html)).

// The maximum number of credits is set by `MAX_CREDIT_COUNT` and will
// saturate at that value if attempting to add more credits. Saturating the
// credit count will pulse `current_credit_count_max` on the next cycle when
// `current_credit_count` updates, and trying to add credits past the limit
// will pulse `add_credit_fail` on the next cycle.

`default_nettype none

module Pipeline_Credit_Gate
#(
    parameter WORD_WIDTH        = 0,
    parameter MAX_CREDIT_COUNT  = 0,

    // Do not set at instantiation, except in Vivado IPI.
    parameter CREDIT_WIDTH      = clog2(MAX_CREDIT_COUNT) + 1 // +1 to hold powers of two exactly
)
(
    input   wire                        clock,
    input   wire                        clear,

    input   wire                        input_data_valid,
    output  wire                        input_data_ready,
    input   wire    [WORD_WIDTH-1:0]    input_data,

    input   wire                        add_credit_pulse,
    output  wire                        add_credit_fail,
    output  wire    [CREDIT_WIDTH-1:0]  current_credit_count,
    output  wire                        current_credit_count_max,
    output  wire                        current_credit_count_zero,

    output  wire                        output_data_valid,
    input   wire                        output_data_ready,
    output  wire    [WORD_WIDTH-1:0]    output_data
);

    `include "clog2_function.vh"

    localparam CREDIT_ZERO = {CREDIT_WIDTH{1'b0}};
    localparam CREDIT_ONE  = {{CREDIT_WIDTH-1{1'b0}},1'b1};

// Obviously, we need a Pipeline Gate at the heart of this module.

    reg open_gate = 1'b0;

    always @(*) begin
        open_gate = (current_credit_count_zero == 1'b0);
    end

    Pipeline_Gate
    #(
        .WORD_WIDTH     (WORD_WIDTH),
        .IMPLEMENTATION ("AND"),
        .GATE_DATA      (0)
    )
    pipeline_gate
    (
        .enable         (open_gate),

        .input_ready    (input_data_ready),
        .input_valid    (input_data_valid),
        .input_data     (input_data),

        .output_valid   (output_data_valid),
        .output_ready   (output_data_ready),
        .output_data    (output_data)
    );

// And a way to count credits and saturate at the max count.

// We cannot add pipe stages to the accumulator, else the adding/consuming of
// credits takes multiple cycles and that both requires more pipeline logic,
// and divides the througput by the number of pipe stages!

    reg credit_incr_decr        = 1'b0;
    reg credit_incr_decr_valid  = 1'b0;

    Accumulator_Binary_Saturating
    #(
        .EXTRA_PIPE_STAGES  (0), // DO NOT CHANGE. MUST BE 0 OR WILL NOT OPERATE PROPERLY (NO HANDLING OF "DONE" LATENCY)
        .WORD_WIDTH         (CREDIT_WIDTH),
        .INITIAL_VALUE      (CREDIT_ZERO)
    )
    credit_counter
    (
        .clock                              (clock),
        .clock_enable                       (1'b1),

        .clear                              (clear),
        // verilator lint_off PINCONNECTEMPTY
        .clear_done                         (),
        // verilator lint_on  PINCONNECTEMPTY

        .increment_carry_in                 (1'b0),
        .increment_add_sub                  (credit_incr_decr), // 0/1 --> +/-
        .increment_value                    (CREDIT_ONE),
        .increment_valid                    (credit_incr_decr_valid),
        // verilator lint_off PINCONNECTEMPTY
        .increment_done                     (),
        // verilator lint_on  PINCONNECTEMPTY

        .load_value                         (CREDIT_ZERO),
        .load_valid                         (1'b0),
        // verilator lint_off PINCONNECTEMPTY
        .load_done                          (),
        // verilator lint_on  PINCONNECTEMPTY

        .limit_max                          (MAX_CREDIT_COUNT [CREDIT_WIDTH-1:0]),
        .limit_min                          (CREDIT_ZERO),

        // verilator lint_off PINCONNECTEMPTY
        .accumulated_value                  (current_credit_count),
        .accumulated_value_carry_out        (),
        .accumulated_value_carries          (),
        .accumulated_value_at_limit_max     (current_credit_count_max),
        .accumulated_value_over_limit_max   (add_credit_fail),
        .accumulated_value_at_limit_min     (current_credit_count_zero),
        .accumulated_value_under_limit_min  ()
        // verilator lint_on  PINCONNECTEMPTY
    );

// Finally, the control logic. We can simply track the input handshake since
// the Pipeline Gate is unbuffered (combinational).

    localparam CREDIT_INCREMENT = 1'b0;
    localparam CREDIT_DECREMENT = 1'b1;

    reg handshake_done = 1'b0;

    always @(*) begin
        handshake_done          = (input_data_ready == 1'b1) && (input_data_valid == 1'b1);
        credit_incr_decr        = (handshake_done   == 1'b1) ? CREDIT_DECREMENT : CREDIT_INCREMENT;
        credit_incr_decr        = (add_credit_pulse == 1'b1) ? CREDIT_INCREMENT : credit_incr_decr;
        credit_incr_decr_valid  = (handshake_done != add_credit_pulse);
    end

endmodule

