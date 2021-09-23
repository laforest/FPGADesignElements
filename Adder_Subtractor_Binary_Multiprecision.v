
//# Multiprecision Binary Integer Adder/Subtractor

// A signed binary integer adder/subtractor, which does arithmetic over
// `WORD_WIDTH` words as a sequence of smaller `STEP_WORD_WIDTH` operations to
// save area and increase operating speed at the price of extra latency.

// The main use of this circuit is to avoid CAD problems which can emerge at
// large integer bit widths (e.g.: 128 bits): the area of added pipeline
// registers would become quite large, and the CAD tools can fail to retime
// them completely into the extra-wide adder logic, thus failing to reach
// a high operating frequency and slowing down the rest of the system.  *There
// are notes in the code which point out the critical paths you can expect to
// see (or not).*

// Also, if we don't need a result every cycle, regular pipelining is
// wasteful: it unnecessarily duplicates the input/output data storage, and
// makes poor use of the adder/subtractor logic (e.g.: the least-significant
// bits are used once, then sit idle for multiple cycles while the higher bits
// are computed).

// Since the result latency depends on the ratio of `WORD_WIDTH` to
// `STEP_WORD_WIDTH` and whether that ratio is a whole integer, the inputs are
// set with a ready/valid handshake, and can be updated after the output
// handshake completes.

// Addition/subtraction is selected with `add_sub`: 0 for an add (`A+B`), and
// 1 for a subtract (`A-B`). This assignment conveniently matches the
// convention of sign bits. *Note that the `overflow` bit is only meaningful
// for signed numbers. For unsigned numbers, use `carry_out` instead.*

//## Ports and Constants

`default_nettype none

module Adder_Subtractor_Binary_Multiprecision
#(
    parameter WORD_WIDTH        = 0,
    parameter STEP_WORD_WIDTH   = 0
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
    output  reg                         overflow
);

    initial begin
        input_ready     = 1'b1; // Ready after reset.
        output_valid    = 1'b0;
        carry_out       = 1'b0;
        overflow        = 1'b0;
    end

    `include "word_count_function.vh"
    `include "word_pad_function.vh"
    `include "clog2_function.vh"

    localparam WORD_ZERO = {WORD_WIDTH{1'b0}};

// Compute how many `STEP_WORD_WIDTH` words we will need to hold
// a `WORD_WIDTH` input. The total width may end up larger, but we will
// discard the extra bits at the end.

    localparam STEP_WORD_COUNT = word_count(WORD_WIDTH, STEP_WORD_WIDTH);
    localparam STEP_WORD_WIDTH_TOTAL = STEP_WORD_WIDTH * STEP_WORD_COUNT;

    localparam STEP_WORD_ZERO  = {STEP_WORD_WIDTH{1'b0}};
    localparam STEP_TOTAL_ZERO = {STEP_WORD_WIDTH_TOTAL{1'b0}};

// How many pad bits at the end of the last step word?  Re-adjust to zero (see
// [Word Pad](./word_pad_function.html) for why) since we don't construct
// a pad here, only index to its position in the last step word.    

    localparam PAD_WIDTH_RAW   = word_pad(WORD_WIDTH, STEP_WORD_WIDTH);
    localparam PAD_WIDTH       = (PAD_WIDTH_RAW == STEP_WORD_WIDTH) ? 0 : PAD_WIDTH_RAW;

// We must add a bit of width to the step counter to deal with the special
// case where `STEP_WORD_WIDTH` equals `WORD_WIDTH`, so the `STEP_WORD_COUNT`
// is 1, and thus the counter would be of width zero, which is impossible.
// The overhead is insignificant and grows logarithmically at worst.

    localparam STEP_COUNT_WIDTH   = clog2(STEP_WORD_COUNT) + 1;
    localparam STEP_COUNT_INITIAL = STEP_WORD_COUNT - 1;
    localparam STEP_ONE           = {{STEP_COUNT_WIDTH-1{1'b0}},1'b1};
    localparam STEP_ZERO          = {STEP_COUNT_WIDTH{1'b0}};

//## Datapath

//### Carry Bit Storage

// Set the initial `step_carry_in` into the step adder/subtractor to 1 (which
// matches the `add_sub` convention) if subtracting to complete the negation
// of the inverted `B` operand, and update it at each calculation step with the
// `step_carry_out`.  The final `carry_out` is calculated later, and depends on
// the `PAD_WIDTH`.

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

//### Input Pipeline for A

// Extend A to the total width of the pipeline as a signed integer.

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

// Word-reverse `A_extended` so the pipeline outputs the least significant
// step word first.

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

// Read `A_extended` into the pipeline, and feed it out one step word at
// a time, from least to most-significant.

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

// Invert `B` if subtracting. The `step_carry_in` is already correctly
// initialized to 1 to make it into a negation.

// We do the negation of `B` in this module instead of using the built-in
// negation logic in the `Adder_Subtractor_Binary` sub-module because I could
// not predict what logic would synthesize when subtracting, which is
// internally be implemented as `A+((~B)+1)-carry_in`. So to be sure the logic
// synthesizes predictably, I decided to remove `carry_in` as an input to this
// module and use the internal `carry_storage` as part of the negation of `B`
// when subtracting, which then implements as `A+((~B)+step_carry_in)`.

    reg [WORD_WIDTH-1:0] B_selected = WORD_ZERO;

    always @(*) begin
        B_selected = (add_sub == 1'b1) ? ~B : B;
    end

// Extend B to the total width of the pipeline as a signed integer.

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

// Word-reverse `B_extended` so the pipeline outputs the least significant step
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

// Read `B_extended` into the pipeline , and feed it out one step word at
// a time, from least to most-significant.

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

//### Step Adder Logic 

// *NOTE: the `step_carry_in` and `step_carry_out` storage and wiring was
// defined earlier.*

// We cannot use the built-in `overflow` as if there are pad bits at the MSB
// positions in the last step word, they will falsely disable the overflow and
// carry-out bits. So we calculate the `overflow` and `carry_out` later in
// this module, and the unused logic in `Adder_Subtractor_Binary` will
// optimize away.

// The adder carry-chain should *never* be the critical path. If so, reduce
// `STEP_WORD_WIDTH` as needed.

    wire [STEP_WORD_WIDTH-1:0] step_sum;
    wire [STEP_WORD_WIDTH-1:0] step_carries;

    Adder_Subtractor_Binary
    #(
        .WORD_WIDTH (STEP_WORD_WIDTH)
    )
    step_adder
    (
        .add_sub    (add_sub), // 0/1 -> A+B/A-B
        .carry_in   (step_carry_in),
        .A          (step_A),
        .B          (step_B),
        .sum        (step_sum),
        .carry_out  (step_carry_out),
        .carries    (step_carries),
        // verilator lint_off PINCONNECTEMPTY
        .overflow   ()
        // verilator lint_on  PINCONNECTEMPTY
    );

//### Output Pipeline for Sum

// Store the `step_sum` word-by-word, then word-reverse it back to the
// expected order so we can extract the least-significant `WORD_WIDTH` subset
// which contains the result we want.

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

// Store the carries word-by-word, then word-reverse them back to the expected
// order so we can extract the least-significant `WORD_WIDTH` subset which
// contains the result we want.

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

//### Overflow and Carry-Out Flags

// We gather together the carries from the final `step_sum` (the most
// significant word of the result) and the final `step_carry_in` (which now
// holds the last `step_carry_out`), and select the correct carries, based on
// the amount of padding in the last step word, to compute the `carry_out` and
// the `overflow`. We have to handle all cases, including when there is no
// padding when `STEP_WORD_WIDTH` exactly divides `WORD_WIDTH`.

// The wiring here is constant and only uses 2 bits, so it will never be
// a critical path, regardless of the width of `all_carries`.

    localparam ALL_CARRIES_WIDTH = 1 + STEP_WORD_WIDTH;
    localparam ALL_CARRIES_ZERO  = {ALL_CARRIES_WIDTH{1'b0}};

    reg [ALL_CARRIES_WIDTH-1:0] all_carries   = ALL_CARRIES_ZERO;
    reg                         last_carry_in = 1'b0;

    always @(*) begin
        all_carries     = {step_carry_in, carries_restored [STEP_WORD_WIDTH_TOTAL-1 -: STEP_WORD_WIDTH]};
        last_carry_in   = all_carries [STEP_WORD_WIDTH - PAD_WIDTH - 1];
        carry_out       = all_carries [STEP_WORD_WIDTH - PAD_WIDTH];
        overflow        = (carry_out != last_carry_in);
    end

//## Control Logic

//### States and Storage 

// We accept inputs in `STATE_LOAD`, compute in
// `STATE_CALC`, and present the output in `STATE_DONE`. Once the results are
// read out, we return to `STATE_LOAD`.

// *NOTE: The state encoding is arbitrary. Also, control from `state_storage`
// to the input/output pipelines will tend to be the critical path as
// `WORD_WIDTH` gets larger due to physical distance and routing congestion,
// depending on the target device and CAD tool.*

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

//### Calculation Steps

// Count down the calculation steps until zero, which is how long we stay in
// `STATE_CALC`.

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

//### Input/Output Handshaking

    reg input_handshake_done  = 1'b0;
    reg output_handshake_done = 1'b0;

    always @(*) begin
        input_ready  = (state == STATE_LOAD);
        output_valid = (state == STATE_DONE);
        input_handshake_done  = (input_ready  == 1'b1) && (input_valid  == 1'b1);
        output_handshake_done = (output_ready == 1'b1) && (output_valid == 1'b1);
    end

//### Control Events

    reg input_load  = 1'b0; // Load of input operation and operands.
    reg calculating = 1'b0; // High while doing the calculation steps.
    reg last_calc   = 1'b0; // High during the last calculation step.
    reg output_read = 1'b0; // When the result is read out.

    always @(*) begin
        input_load  = (state == STATE_LOAD) && (input_handshake_done  == 1'b1);
        calculating = (state == STATE_CALC);
        last_calc   = (state == STATE_CALC) && (step_done             == 1'b1);
        output_read = (state == STATE_DONE) && (output_handshake_done == 1'b1);
    end

// After this point, there should be no reference to inputs, outputs, or
// states. All control logic must be expressed in terms of control events.

//### State Transitions

    always @(*) begin
        state_next = (input_load  == 1'b1) ? STATE_CALC : state;
        state_next = (last_calc   == 1'b1) ? STATE_DONE : state_next;
        state_next = (output_read == 1'b1) ? STATE_LOAD : state_next;
    end

//### Datapath Control Signals 

    always @(*) begin
        load_carry_initial  = (input_load  == 1'b1);
        load_carry_step     = (input_load  == 1'b1) || (calculating == 1'b1);
        load_A              = (input_load  == 1'b1);
        load_B              = (input_load  == 1'b1);
        load_step_sum       = (calculating == 1'b1);
        load_step_carries   = (calculating == 1'b1);
        step_do             = (calculating == 1'b1);
        step_load           = (input_load  == 1'b1);
    end

endmodule

