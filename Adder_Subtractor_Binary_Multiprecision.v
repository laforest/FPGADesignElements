//# Multiprecision Binary Integer Adder/Subtractor

// A signed binary integer adder/subtractor, with `carry_in`, `carry_out`,
// `overflow`, and all the intermediate `carries` into each bit position (see
// [Carry-In Calculator](./CarryIn_Binary.html) for their uses).

// Addition/subtraction is selected with `add_sub`: 0 for an add
// (`A+B+carry_in`), and 1 for a subtract (`A-B-carry_in`). This assignment
// conveniently matches the convention of sign bits. Note that the `overflow`
// bit is only meaningful for signed numbers. For unsigned numbers, use
// `carry_out` instead.

// The addition or subtraction over the whole width of the inputs is done as
// multiple steps of lower precision. This minimizes the amount of buffering
// and pipelining required, and avoids P&R issues at large word widths (e.g.:
// 128 bits) which prevent high-speed operation.

`default_nettype none

module Adder_Subtractor_Binary_Multiprecision
#(
    parameter WORD_WIDTH        = 128,
    parameter STEP_WORD_WIDTH   = 16
)
(
    input   wire                        clock,
    input   wire                        clock_enable,
    input   wire                        clear,

    input   wire                        input_valid,
    output  reg                         input_ready,

    input   wire                        add_sub,    // 0/1 -> A+B/A-B
    input   wire    [WORD_WIDTH-1:0]    A,
    input   wire    [WORD_WIDTH-1:0]    B,

    output  reg                         output_valid,
    input   wire                        output_ready,

    output  wire    [WORD_WIDTH-1:0]    sum,
    output  reg                         carry_out,
    output  wire    [WORD_WIDTH-1:0]    carries,
    output  wire                        overflow
);

    initial begin
        input_ready     = 1'b1; // Ready after reset.
        output_valid    = 1'b0;
        carry_out       = 1'b0;
    end

    `include "./word_count_function.vh"
    `include "./word_pad_function.vh"
    `include "./clog2_function.vh"

    localparam WORD_ZERO = {WORD_WIDTH{1'b0}};

    localparam STEP_WORD_COUNT = word_count(WORD_WIDTH, STEP_WORD_WIDTH);
    localparam STEP_WORD_WIDTH_TOTAL = STEP_WORD_WIDTH * STEP_WORD_COUNT;

    localparam STEP_WORD_ZERO  = {STEP_WORD_WIDTH{1'b0}};
    localparam STEP_TOTAL_ZERO = {STEP_WORD_WIDTH_TOTAL{1'b0}};

    // We must add a bit to guarantee that we can represent -1.
    // Else if the counter is one bit (for 2 steps), we can't distinguish -1
    // from 1.
    localparam STEP_COUNT_WIDTH   = clog2(STEP_WORD_COUNT) + 1;
    localparam STEP_COUNT_INITIAL = STEP_WORD_COUNT - 1;
    localparam STEP_ONE           = {{STEP_COUNT_WIDTH-1{1'b0}},1'b1};
    localparam STEP_ZERO          = {STEP_COUNT_WIDTH{1'b0}};
    localparam STEP_MINUS_ONE     = {STEP_COUNT_WIDTH{1'b1}};

//## Datapath

// Store whether we add or sub, which remains constant until reloaded.

//    reg  load_add_sub = 1'b0;    
//    wire add_sub_loaded;
//
//    Register
//    #(
//        .WORD_WIDTH     (1),
//        .RESET_VALUE    (1'b0)
//    )
//    add_sub_storage
//    (
//        .clock          (clock),
//        .clock_enable   (load_add_sub),
//        .clear          (1'b0),
//        .data_in        (add_sub),
//        .data_out       (add_sub_loaded)
//    );

// Set the initial carry_in to 1 (which matches the `add_sub` convention) if
// subtracting to complete the negation of the inverted B operand, and update
// it at each calculation step with the step carry-out.  After the final step,
// this is the final carry-out.

    reg  load_carry_initial     = 1'b0;
    reg  load_carry_step        = 1'b0;
    reg  step_carry_selected    = 1'b0;
    wire step_carry_out;
    wire step_carry_in;

    always @(*) begin
        step_carry_selected = (load_carry_initial == 1'b1) ? add_sub : step_carry_out;
    end 

    Register
    #(
        .WORD_WIDTH     (1),
        .RESET_VALUE    (1'b0)
    )
    carry_storage
    (
        .clock          (clock),
        .clock_enable   (load_carry_step),
        .clear          (1'b0),
        .data_in        (step_carry_selected),
        .data_out       (step_carry_in)
    );

    always @(*) begin
        carry_out = step_carry_in;
    end

//### Input Pipeline for A

// Extend A to the total width of the pipeline. This may mean sign-extending.

    wire [STEP_WORD_WIDTH_TOTAL-1:0] A_extended;

    Width_Adjuster
    #(
        .WORD_WIDTH_IN  (WORD_WIDTH),
        .SIGNED         (1),
        .WORD_WIDTH_OUT (STEP_WORD_WIDTH_TOTAL)
    )
    A_extender
    (
        .original_input     (A),
        .adjusted_output    (A_extended)
    );

// Word-reverse A_extended so the pipeline outputs the least significant step
// word first.

    wire [STEP_WORD_WIDTH_TOTAL-1:0] A_reversed;

    Word_Reverser
    #(
        .WORD_WIDTH (STEP_WORD_WIDTH),
        .WORD_COUNT (STEP_WORD_COUNT)
    )
    A_reverser
    (
        .words_in   (A_extended),
        .words_out  (A_reversed)
    );

// Read in A, and feed it out one step word at a time, from least to
// most-significant.

    reg                        load_A = 1'b0;
    wire [STEP_WORD_WIDTH-1:0] step_A;

    Register_Pipeline
    #(
        .WORD_WIDTH     (STEP_WORD_WIDTH),
        .PIPE_DEPTH     (STEP_WORD_COUNT),
        .RESET_VALUES   (STEP_TOTAL_ZERO)
    )
    A_storage
    (
        .clock          (clock),
        .clock_enable   (clock_enable),
        .clear          (1'b0),
        .parallel_load  (load_A),
        .parallel_in    (A_reversed),
        // verilator lint_off PINCONNECTEMPTY
        .parallel_out   (),
        // verilator lint_on  PINCONNECTEMPTY
        .pipe_in        (STEP_WORD_ZERO),
        .pipe_out       (step_A)
    );

//### Input Pipeline for B

// Invert B if subtracting (the carry_in was set to match to make it
// a negation).

    reg [WORD_WIDTH-1:0] B_selected = WORD_ZERO;

    always @(*) begin
        B_selected = (add_sub == 1'b1) ? ~B : B;
    end

// Extend B to the total width of the pipeline. This may mean sign-extending.

    wire [STEP_WORD_WIDTH_TOTAL-1:0] B_extended;

    Width_Adjuster
    #(
        .WORD_WIDTH_IN  (WORD_WIDTH),
        .SIGNED         (1),
        .WORD_WIDTH_OUT (STEP_WORD_WIDTH_TOTAL)
    )
    B_extender
    (
        .original_input     (B_selected),
        .adjusted_output    (B_extended)
    );

// Word-reverse B_extended so the pipeline outputs the least significant step
// word first.

    wire [STEP_WORD_WIDTH_TOTAL-1:0] B_reversed;

    Word_Reverser
    #(
        .WORD_WIDTH (STEP_WORD_WIDTH),
        .WORD_COUNT (STEP_WORD_COUNT)
    )
    B_reverser
    (
        .words_in   (B_extended),
        .words_out  (B_reversed)
    );

// Read in B, and feed it out one step word at a time, from least to
// most-significant.

    reg                        load_B = 1'b0;
    wire [STEP_WORD_WIDTH-1:0] step_B;

    Register_Pipeline
    #(
        .WORD_WIDTH     (STEP_WORD_WIDTH),
        .PIPE_DEPTH     (STEP_WORD_COUNT),
        .RESET_VALUES   (STEP_TOTAL_ZERO)
    )
    B_storage
    (
        .clock          (clock),
        .clock_enable   (clock_enable),
        .clear          (1'b0),
        .parallel_load  (load_B),
        .parallel_in    (B_reversed),
        // verilator lint_off PINCONNECTEMPTY
        .parallel_out   (),
        // verilator lint_on  PINCONNECTEMPTY
        .pipe_in        (STEP_WORD_ZERO),
        .pipe_out       (step_B)
    );

//### Adder Logic (we only add, as B was negated before if subtracting)

// Note: the carry_in and carry_out storage and wiring was defined earlier.

    wire [STEP_WORD_WIDTH-1:0] step_sum;
    wire [STEP_WORD_WIDTH-1:0] step_carries;
    wire                       step_overflow;

    Adder_Subtractor_Binary
    #(
        .WORD_WIDTH (STEP_WORD_WIDTH)
    )
    step_adder
    (
        .add_sub    (1'b0), // 0/1 -> A+B/A-B
        .carry_in   (step_carry_in),
        .A          (step_A),
        .B          (step_B),
        .sum        (step_sum),
        .carry_out  (step_carry_out),
        .carries    (step_carries),
        .overflow   (step_overflow)
    );

//### Output Pipeline for Sum

// Store the sum word-by-word, then word-reverse it back to the expected order
// so we can extract the WORD_WIDTH subset which we want.

    reg                              load_step_sum = 1'b0;
    wire [STEP_WORD_WIDTH_TOTAL-1:0] sum_reversed;
    wire [STEP_WORD_WIDTH_TOTAL-1:0] sum_restored;

    Register_Pipeline
    #(
        .WORD_WIDTH     (STEP_WORD_WIDTH),
        .PIPE_DEPTH     (STEP_WORD_COUNT),
        .RESET_VALUES   (STEP_TOTAL_ZERO)
    )
    output_sum
    (
        .clock          (clock),
        .clock_enable   (load_step_sum),
        .clear          (1'b0),
        .parallel_load  (1'b0),
        .parallel_in    (STEP_TOTAL_ZERO),
        .parallel_out   (sum_reversed),
        .pipe_in        (step_sum),
        // verilator lint_off PINCONNECTEMPTY
        .pipe_out       ()
        // verilator lint_on  PINCONNECTEMPTY
    );

    Word_Reverser
    #(
        .WORD_WIDTH (STEP_WORD_WIDTH),
        .WORD_COUNT (STEP_WORD_COUNT)
    )
    sum_reverser
    (
        .words_in   (sum_reversed),
        .words_out  (sum_restored)
    );

    Width_Adjuster
    #(
        .WORD_WIDTH_IN  (STEP_WORD_WIDTH_TOTAL),
        .SIGNED         (1),
        .WORD_WIDTH_OUT (WORD_WIDTH)
    )
    sum_truncator
    (
        .original_input     (sum_restored),
        .adjusted_output    (sum)
    );

//### Output Pipeline for Carries

// Store the carries word-by-word, then word-reverse them back to the expected order
// so we can extract the WORD_WIDTH subset which we want.

    reg                              load_step_carries = 1'b0;
    wire [STEP_WORD_WIDTH_TOTAL-1:0] carries_reversed;
    wire [STEP_WORD_WIDTH_TOTAL-1:0] carries_restored;

    Register_Pipeline
    #(
        .WORD_WIDTH     (STEP_WORD_WIDTH),
        .PIPE_DEPTH     (STEP_WORD_COUNT),
        .RESET_VALUES   (STEP_TOTAL_ZERO)
    )
    output_carries
    (
        .clock          (clock),
        .clock_enable   (load_step_carries),
        .clear          (1'b0),
        .parallel_load  (1'b0),
        .parallel_in    (STEP_TOTAL_ZERO),
        .parallel_out   (carries_reversed),
        .pipe_in        (step_carries),
        // verilator lint_off PINCONNECTEMPTY
        .pipe_out       ()
        // verilator lint_on  PINCONNECTEMPTY
    );

    Word_Reverser
    #(
        .WORD_WIDTH (STEP_WORD_WIDTH),
        .WORD_COUNT (STEP_WORD_COUNT)
    )
    carries_reverser
    (
        .words_in   (carries_reversed),
        .words_out  (carries_restored)
    );

    Width_Adjuster
    #(
        .WORD_WIDTH_IN  (STEP_WORD_WIDTH_TOTAL),
        .SIGNED         (0),
        .WORD_WIDTH_OUT (WORD_WIDTH)
    )
    carries_truncator
    (
        .original_input     (carries_restored),
        .adjusted_output    (carries)
    );

//### Output Storage for Overflow

// Update the overflow at each step. Correct after the final step.

    reg load_step_overflow = 1'b0;

    Register
    #(
        .WORD_WIDTH     (1),
        .RESET_VALUE    (1'b0)
    )
    output_overflow
    (
        .clock          (clock),
        .clock_enable   (load_step_overflow),
        .clear          (1'b0),
        .data_in        (step_overflow),
        .data_out       (overflow)
    );

//## Control Logic

// Define states and storage.

    localparam STATE_WIDTH                   = 2;
    localparam [STATE_WIDTH-1:0] STATE_LOAD  = 2'b00;
    localparam [STATE_WIDTH-1:0] STATE_CALC  = 2'b01;
    localparam [STATE_WIDTH-1:0] STATE_DONE  = 2'b11;
    localparam [STATE_WIDTH-1:0] STATE_ERROR = 2'b10; // Never reached.

    wire [STATE_WIDTH-1:0] state;
    reg  [STATE_WIDTH-1:0] state_next = STATE_LOAD;

    Register
    #(
        .WORD_WIDTH     (STATE_WIDTH),
        .RESET_VALUE    (STATE_LOAD)
    )
    state_storage
    (
        .clock          (clock),
        .clock_enable   (clock_enable),
        .clear          (clear),
        .data_in        (state_next),
        .data_out       (state)
    );

// Count the calculation steps.

    reg                         step_do     = 1'b0;
    reg                         step_load   = 1'b0;
    wire [STEP_COUNT_WIDTH-1:0] step;

    Counter_Binary
    #(
        .WORD_WIDTH     (STEP_COUNT_WIDTH),
        .INCREMENT      (STEP_ONE),
        .INITIAL_COUNT  (STEP_COUNT_INITIAL [STEP_COUNT_WIDTH-1:0])
    )
    calc_steps
    (
        .clock          (clock),
        .clear          (clear),

        .up_down        (1'b1), // 0/1 --> up/down
        .run            (step_do),

        .load           (step_load),
        .load_count     (STEP_COUNT_INITIAL [STEP_COUNT_WIDTH-1:0]),

        .carry_in       (1'b0),
        // verilator lint_off PINCONNECTEMPTY
        .carry_out      (),
        .carries        (),
        .overflow       (),
        // verilator lint_on  PINCONNECTEMPTY

        .count          (step)
    );

    reg step_done = 1'b0;

    always @(*) begin
        step_done = (step == STEP_ZERO);
    end

// Do the input/output handshaking

    reg input_handshake_done  = 1'b0;
    reg output_handshake_done = 1'b0;

    always @(*) begin
        input_ready  = (state == STATE_LOAD);
        output_valid = (state == STATE_DONE);
        input_handshake_done  = (input_ready  == 1'b1) && (input_valid  == 1'b1);
        output_handshake_done = (output_ready == 1'b1) && (output_valid == 1'b1);
    end

// What are the significant events?

    reg input_load      = 1'b0; // Load of input operation and operands.
    reg calculating     = 1'b0; // Are we doing the calculation steps?
    reg calc_done       = 1'b0; // When all calculation steps are done and the result is valid.
    reg output_read     = 1'b0; // When the result is read out.
    reg read_and_load   = 1'b0; // When the result is read out and new inputs loaded at the same time.

    always @(*) begin
        input_load    = (state == STATE_LOAD) && (input_handshake_done  == 1'b1);
        calculating   = (state == STATE_CALC);
        calc_done     = (state == STATE_CALC) && (step_done             == 1'b1);
        output_read   = (state == STATE_DONE) && (output_handshake_done == 1'b1) && (input_handshake_done == 1'b0);
        read_and_load = (state == STATE_DONE) && (output_handshake_done == 1'b1) && (input_handshake_done == 1'b1);
    end

// Do the next state calculations

    always @(*) begin
        state_next = (input_load    == 1'b1) ? STATE_CALC : state;
        state_next = (calc_done     == 1'b1) ? STATE_DONE : state_next;
        state_next = (output_read   == 1'b1) ? STATE_LOAD : state_next;
        state_next = (read_and_load == 1'b1) ? STATE_CALC : state_next;
    end

// Control the datapath

    always @(*) begin
        load_carry_initial  = (input_load == 1'b1) || (read_and_load == 1'b1);
        load_carry_step     = (load_carry_initial == 1'b1) || (calculating == 1'b1);
        load_A              = (load_carry_initial == 1'b1);
        load_B              = (load_carry_initial == 1'b1);
        load_step_sum       = (calculating == 1'b1);
        load_step_carries   = (calculating == 1'b1);
        load_step_overflow  = (calculating == 1'b1);
        step_do             = (calculating  == 1'b1);
        step_load           = (load_carry_initial == 1'b1);
    end

endmodule

