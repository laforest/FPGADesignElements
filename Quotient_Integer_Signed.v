
//# Signed Integer Quotient

// Computes the signed quotient of the signed dividend and divisor, using
// truncating long division, which matches the behaviour of most programming
// languages and manual long division. For example, here are the expected
// values:

// *  22 /   7 =  3 rem  1
// * -22 /   7 = -3 rem -1
// *  22 /  -7 = -3 rem  1
// * -22 /  -7 =  3 rem -1
// *   7 /  22 =  0 rem  7
// *  -7 / -22 =  0 rem -7
// *  -7 /  22 =  0 rem -7
// *   7 / -22 =  0 rem  7
// *   0 /   0 = -1 rem  0 (raises div_by_zero)
// *  22 /   0 = -1 rem 22 (raises div_by_zero)
// * -22 /   0 =  1 rem 22 (raises div_by_zero)

// NOTE: depends on the output of the remainder calculations.

`default_nettype none

module Quotient_Integer_Signed
#(
    parameter WORD_WIDTH        = 8,
    parameter PIPELINE_STAGES   = 0
)
(
    input  wire                     clock,
    input  wire                     clear,

    input  wire                     input_valid,
    output reg                      input_ready,
    input  wire                     dividend_sign,
    input  wire                     divisor_sign,

    output reg                      output_valid,
    input  wire                     output_ready,
    output wire [WORD_WIDTH-1:0]    quotient,
    
    input  wire                     control_valid,
    output reg                      control_ready,
    input  wire                     step_ok
);

    `include "clog2_function.vh"

    localparam WORD_ZERO = {WORD_WIDTH{1'b0}};

    initial begin
        input_ready      = 1'b0;
        output_valid     = 1'b0;
        control_ready    = 1'b0;
    end

// Some basic definitions to establish our two's-complement signed
// representation.

    localparam ADD = 1'b0;
    localparam SUB = 1'b1;

// We have to internally compute with one extra bit of range to allow the
// minimum signed number to be expressible as an unsigned number. Else, we
// cannot subtract any multiple of itself from this minimum signed number
// (e.g. -8/1 needs to add +8 to the remainder to reach "1 rem 0", and with
// the minimum number of bits (4), we can only represent up to +7)

    localparam WORD_WIDTH_LONG  = WORD_WIDTH + 1;
    localparam WORD_ZERO_LONG   = {WORD_WIDTH_LONG{1'b0}};
    localparam WORD_ONE_LONG    = {{WORD_WIDTH_LONG-1{1'b0}},1'b1};
    localparam WORD_ONES_LONG   = {WORD_WIDTH_LONG{1'b1}};

//## Data Path

//### Input Signs

    reg  divisor_sign_enable = 1'b0;
    wire divisor_sign_loaded;

    Register
    #(
        .WORD_WIDTH     (1),
        .RESET_VALUE    (1'b0)
    )
    divisor_sign_storage
    (
        .clock          (clock),
        .clock_enable   (divisor_sign_enable),
        .clear          (1'b0),
        .data_in        (divisor_sign),
        .data_out       (divisor_sign_loaded)
    );

    reg  dividend_sign_enable = 1'b0;
    wire dividend_sign_loaded;

    Register
    #(
        .WORD_WIDTH     (1),
        .RESET_VALUE    (1'b0)
    )
    dividend_sign_storage
    (
        .clock          (clock),
        .clock_enable   (dividend_sign_enable),
        .clear          (1'b0),
        .data_in        (dividend_sign),
        .data_out       (dividend_sign_loaded)
    );

//### Quotient Increment

// The quotient increment which is added/subtracted to/from the quotient each
// time we could remove the divisor from the remainder.  Shift it right by
// 1 each calculation step, so we increment by decreasing multiples of 2 at
// each division step.

    reg                         quotient_increment_enable   = 1'b0;
    reg                         quotient_increment_load     = 1'b0;
    wire [WORD_WIDTH_LONG-1:0]  quotient_increment_reversed;

    Register_Pipeline
    #(
        .WORD_WIDTH     (1),
        .PIPE_DEPTH     (WORD_WIDTH_LONG),
        // concatenation of each stage initial/reset value
        .RESET_VALUES   (WORD_ZERO_LONG)
    )
    quotient_increment_storage
    (
        .clock          (clock),
        .clock_enable   (quotient_increment_enable),
        .clear          (clear),
        .parallel_load  (quotient_increment_load),
        .parallel_in    (WORD_ONE_LONG),
        .parallel_out   (quotient_increment_reversed),
        .pipe_in        (1'b0),
        // verilator lint_off PINCONNECTEMPTY
        .pipe_out       ()
        // verilator lint_on  PINCONNECTEMPTY
    );

// The Register_Pipeline only shifts left, so let's reverse its parallel
// output.

    wire [WORD_WIDTH_LONG-1:0]  quotient_increment;

    Word_Reverser
    #(
        .WORD_WIDTH (1),
        .WORD_COUNT (WORD_WIDTH_LONG)
    )
    quotient_increment_shift_direction
    (
        .words_in   (quotient_increment_reversed),
        .words_out  (quotient_increment)
    );

//### Quotient

    reg                         quotient_enable = 1'b0;
    reg                         quotient_clear  = 1'b0;
    wire [WORD_WIDTH_LONG-1:0]  quotient_next;
    wire [WORD_WIDTH_LONG-1:0]  quotient_loaded;

    Register
    #(
        .WORD_WIDTH     (WORD_WIDTH_LONG),
        .RESET_VALUE    (WORD_ZERO_LONG)
    )
    quotient_storage
    (
        .clock          (clock),
        .clock_enable   (quotient_enable),
        .clear          (quotient_clear),
        .data_in        (quotient_next),
        .data_out       (quotient_loaded)
    );

    Width_Adjuster
    #(
        .WORD_WIDTH_IN  (WORD_WIDTH_LONG),
        .SIGNED         (1),
        .WORD_WIDTH_OUT (WORD_WIDTH)
    )
    quotient_shorten
    (
        // It's possible some input bits are truncated away
        // verilator lint_off UNUSED
        .original_input     (quotient_loaded),
        // verilator lint_on  UNUSED
        .adjusted_output    (quotient)
    );

//### Pipeline

// Now, run all stored data through a pipeline. We expect forward register
// retiming to push the pipeline registers, if any, through the following
// arithmetic logic to reduce the critical path delay.

    localparam PIPELINE_WIDTH = 1 + 1 + WORD_WIDTH_LONG + WORD_WIDTH_LONG;

    wire                        divisor_sign_loaded_pipelined;
    wire                        dividend_sign_loaded_pipelined;
    wire [WORD_WIDTH_LONG-1:0]  quotient_increment_pipelined;
    wire [WORD_WIDTH_LONG-1:0]  quotient_loaded_pipelined;

    Register_Pipeline_Simple
    #(
        .WORD_WIDTH (PIPELINE_WIDTH),
        .PIPE_DEPTH (PIPELINE_STAGES)
    )
    calculation_pipeline
    (
        .clock          (clock),
        .clock_enable   (1'b1),
        .clear          (1'b0),
        .pipe_in        ({divisor_sign_loaded,           dividend_sign_loaded,           quotient_increment,           quotient_loaded}),
        .pipe_out       ({divisor_sign_loaded_pipelined, dividend_sign_loaded_pipelined, quotient_increment_pipelined, quotient_loaded_pipelined})
    );

//### Quotient Calculation

    reg quotient_add_sub = 1'b0;

    always @(*) begin
        quotient_add_sub = (divisor_sign_loaded_pipelined == dividend_sign_loaded_pipelined) ? ADD : SUB;
    end

    Adder_Subtractor_Binary
    #(
        .WORD_WIDTH (WORD_WIDTH_LONG)
    )
    quotient_calc
    (
        .add_sub    (quotient_add_sub), // 0/1 -> A+B/A-B
        .carry_in   (1'b0),
        .A          (quotient_loaded_pipelined),
        .B          (quotient_increment_pipelined),
        .sum        (quotient_next),
        // verilator lint_off PINCONNECTEMPTY
        .carry_out  (),
        .carries    (),
        .overflow   ()
        // verilator lint_on  PINCONNECTEMPTY
    );

//## Control Path

// Each calculation takes `WORD_WIDTH_LONG` steps, from `WORD_WIDTH_LONG-1` to `0`, plus
// one step to initially load the dividend and divisor. Thus, we need
// a counter of the correct width.

    localparam STEPS_WIDTH      = clog2(WORD_WIDTH_LONG);
    localparam STEPS_INITIAL    = WORD_WIDTH_LONG - 1;
    localparam STEPS_ZERO       = {STEPS_WIDTH{1'b0}};
    localparam STEPS_ONE        = {{STEPS_WIDTH-1{1'b0}},1'b1};

// We need a pipelining counter so we save the result of a division step only
// once the calculation has propagated through the whole pipeline.  Since the
// pipeline depth can be zero, we have to do some contortions to avoid
// clog2(0) and replications of length zero (which are not legal outside of
// a larger concatenation).

    localparam PIPELINE_STAGES_TOTAL  = PIPELINE_STAGES + 1;
    localparam PIPELINE_STEPS_WIDTH   = (PIPELINE_STAGES_TOTAL == 1) ? 1 : clog2(PIPELINE_STAGES_TOTAL);
    localparam PIPELINE_STEPS_INITIAL = PIPELINE_STAGES_TOTAL - 1;
    localparam PIPELINE_STEPS_ZERO    = {PIPELINE_STEPS_WIDTH{1'b0}};
    localparam PIPELINE_STEPS_ONE     = {{PIPELINE_STEPS_WIDTH-1{1'b0}},1'b1};

// We denote state as two bits, with the following transitions:
// LOAD -> CALC -> DONE -> LOAD -> ... 
// We don't handle the fourth, impossible case.
// We don't have a state for when a calculation step completes, as
// PIPELINE_STAGES may be zero, so each cycle is a step.

// FIXME: Why this encoding choice? Is it faster to decode? Easier to debug?

    localparam                      STATE_WIDTH     = 2;
    localparam [STATE_WIDTH-1:0]    STATE_LOAD      = 'b00;
    localparam [STATE_WIDTH-1:0]    STATE_CALC      = 'b10;
    localparam [STATE_WIDTH-1:0]    STATE_DONE      = 'b11;
    localparam [STATE_WIDTH-1:0]    STATE_ERROR     = 'b01; // Never reached

// The state bits, from which we derive the control outputs and the internal
// control signals.

    reg  [STATE_WIDTH-1:0]  state_next = STATE_LOAD;
    wire [STATE_WIDTH-1:0]  state;

    Register
    #(
        .WORD_WIDTH     (STATE_WIDTH),
        .RESET_VALUE    (STATE_LOAD)
    )
    state_storage
    (
        .clock          (clock),
        .clock_enable   (1'b1),
        .clear          (clear),
        .data_in        (state_next),
        .data_out       (state)
    );

// Count down WORD_WIDTH-1 calculation steps. Stops at zero, and reloads when
// leaving STATE_LOAD.

    reg                     calculation_step_clear  = 1'b0;
    reg                     calculation_step_do     = 1'b0;
    wire [STEPS_WIDTH-1:0]  calculation_step;

    Counter_Binary
    #(
        .WORD_WIDTH     (STEPS_WIDTH),
        .INCREMENT      (STEPS_ONE),
        .INITIAL_COUNT  (STEPS_INITIAL [STEPS_WIDTH-1:0])
    )
    calculation_steps
    (
        .clock          (clock),
        .clear          (calculation_step_clear),

        .up_down        (1'b1),         // 0/1 -> up/down
        .run            (calculation_step_do),

        .load           (1'b0),
        .load_count     (STEPS_ZERO),

        .carry_in       (1'b0),
        // verilator lint_off PINCONNECTEMPTY
        .carry_out      (),
        .carries        (),
        .overflow       (),
        // verilator lint_on  PINCONNECTEMPTY
        .count          (calculation_step)
    );

// Count down PIPELINE_STAGES steps for each division step.

    reg                             pipeline_step_clear  = 1'b0;
    reg                             pipeline_step_do     = 1'b0;
    wire [PIPELINE_STEPS_WIDTH-1:0] pipeline_step;

    Counter_Binary
    #(
        .WORD_WIDTH     (PIPELINE_STEPS_WIDTH),
        .INCREMENT      (PIPELINE_STEPS_ONE),
        .INITIAL_COUNT  (PIPELINE_STEPS_INITIAL [PIPELINE_STEPS_WIDTH-1:0])
    )
    pipeline_steps
    (
        .clock          (clock),
        .clear          (pipeline_step_clear),
        .up_down        (1'b1),         // 0/1 -> up/down
        .run            (pipeline_step_do),
        .load           (1'b0),
        .load_count     (PIPELINE_STEPS_ZERO),
        .carry_in       (1'b0),
        // verilator lint_off PINCONNECTEMPTY
        .carry_out      (),
        .carries        (),
        .overflow       (),
        // verilator lint_on  PINCONNECTEMPTY
        .count          (pipeline_step)
    );

// First, the input and output handshakes. To avoid long combination paths,
// ready and valid should not depend directly on eachother.

// Accept inputs when empty (after results are read out) or frehsly
// reset/cleared). Declare outputs valid when calculation is done.
// Signal a new calculation step each time we pass through the pipeline (if
// any).

    always @(*) begin
        output_valid   = (state == STATE_DONE);
        input_ready    = (state == STATE_LOAD);
        control_ready  = (state == STATE_CALC) && (pipeline_step == PIPELINE_STEPS_ZERO);
    end

// Then, define the basic interactions with and transformations within this
// module.  Past this point, we should not refer directly to the FSM states,
// but to these events which are combinations of states and signals.

    reg load_inputs       = 1'b0; // When we load the dividend and divisor signs.
    reg read_outputs      = 1'b0; // When we read out the quotient.
    reg read_control      = 1'b0; // When we read in the calculation step status.
    reg calculating       = 1'b0; // High while performing the division steps.
    reg step_done         = 1'b0; // High when a calculation exits the pipeline and is ack'ed by other computations.
    reg last_calculation  = 1'b0; // High during the last calculation step.

    always @(*) begin
        load_inputs       = (input_ready   == 1'b1) && (input_valid   == 1'b1);
        read_outputs      = (output_valid  == 1'b1) && (output_ready  == 1'b1);
        read_control      = (control_valid == 1'b1) && (control_ready == 1'b1);
        calculating       = (state == STATE_CALC);
        step_done         = (read_control == 1'b1);
        last_calculation  = (read_control == 1'b1) && (calculation_step == STEPS_ZERO);
    end

// Define the running state machine transitions. There is no handling of erroneous states.

    always @(*) begin
        state_next = (load_inputs       == 1'b1) ? STATE_CALC : state;
        state_next = (last_calculation  == 1'b1) ? STATE_DONE : state_next;
        state_next = (read_outputs      == 1'b1) ? STATE_LOAD : state_next;
    end

// Control the calculation step counter

    always @(*) begin
        calculation_step_clear = (load_inputs == 1'b1) || (clear == 1'b1);
        calculation_step_do    = (step_done   == 1'b1);
    end

// Control the pipeline step counter

    always @(*) begin
        pipeline_step_clear = (step_done == 1'b1) || (clear == 1'b1);
        pipeline_step_do    = (calculating == 1'b1) && (pipeline_step != PIPELINE_STEPS_ZERO);
    end

// Control the divisor and dividend signs

    always @(*) begin
        divisor_sign_enable  = (load_inputs == 1'b1);
        dividend_sign_enable = (load_inputs == 1'b1);
    end

// Control the quotient and quotient increment

    always @(*) begin
        quotient_increment_enable = (load_inputs == 1'b1) || (step_done == 1'b1);
        quotient_increment_load   = (load_inputs == 1'b1);
        quotient_enable           = (load_inputs == 1'b1) || ((step_done == 1'b1) && (step_ok == 1'b1));
        quotient_clear            = (load_inputs == 1'b1) || (clear == 1'b1);
    end

endmodule 

