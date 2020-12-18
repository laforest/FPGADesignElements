
//# Signed Integer Remainder

// Computes the signed remainder of the signed dividend and divisor, using
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

//## Interface and Latency

// The calculation starts after any pending results have been read out by the
// output ready/valid handshake, and an input ready/valid handshake provides
// a new dividend and divisor. A calculation takes WORD_WIDTH
// * PIPELINE_STAGES cycles, plus one for the initial load, plus one for the
// result read out.

//## General Theory of Operation

// Think of the dividend and divisor as points along a number line. Depending
// on their initial signs, we will add or subtract the divisor to/from the
// dividend as necessary *to bring the dividend towards zero*. No final
// calculations of absolute values or sign corrections are necessary, which
// saves a lot of hardware and cycles.


`default_nettype none

module Remainder_Integer_Signed
#(
    parameter WORD_WIDTH        = 8,
    parameter PIPELINE_STAGES   = 0
)
(
    input  wire                     clock,
    input  wire                     clear,

    input  wire                     input_valid,
    output reg                      input_ready,
    input  wire [WORD_WIDTH-1:0]    dividend,
    input  wire [WORD_WIDTH-1:0]    divisor,

    output reg                      output_valid,
    input  wire                     output_ready,
    output wire [WORD_WIDTH-1:0]    remainder,
    output wire                     divide_by_zero,
    
    output reg                      control_valid,
    input  wire                     control_ready,
    output reg                      step_ok
);

    `include "clog2_function.vh"

    localparam WORD_ZERO = {WORD_WIDTH{1'b0}};

    initial begin
        input_ready      = 1'b0;
        output_valid     = 1'b0;
        control_valid    = 1'b0;
        step_ok          = 1'b0;
    end

// Some basic definitions to establish our two's-complement signed
// representation.

    localparam ADD              = 1'b0;
    localparam SUB              = 1'b1;
    localparam POSITIVE         = 1'b0;
    localparam NEGATIVE         = 1'b1;

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

//### Divisor and Remainder Increment

    wire [WORD_WIDTH_LONG-1:0] divisor_long;

    Width_Adjuster
    #(
        .WORD_WIDTH_IN  (WORD_WIDTH),
        .SIGNED         (1),
        .WORD_WIDTH_OUT (WORD_WIDTH_LONG)
    )
    divisor_extend
    (
        // It's possible some input bits are truncated away
        // verilator lint_off UNUSED
        .original_input     (divisor),
        // verilator lint_on  UNUSED
        .adjusted_output    (divisor_long)
    );

// Extract and store the initial sign of the divisor.

    reg  divisor_sign_initial_load = 1'b0;
    wire divisor_sign_initial;

    Register
    #(
        .WORD_WIDTH     (1),
        .RESET_VALUE    (1'b0)
    )
    divisor_sign_initial_storage
    (
        .clock          (clock),
        .clock_enable   (divisor_sign_initial_load),
        .clear          (1'b0),
        .data_in        (divisor_long [WORD_WIDTH_LONG-1]),
        .data_out       (divisor_sign_initial)
    );

// Store the divisor aside and shift its LSB into the MSB of the
// remainder_increment at each division step, while sign-extending the
// divisor. The initial load does the first shift implicitly.

// NOTE: we do the signed shift right manually rather than use the Verilog
// operator ">>>" since that would need us to declare divisor_long, and only
// it, signed, which is asking for unexpected bugs.

    reg                         divisor_enable  = 1'b0;
    reg                         divisor_load    = 1'b0;
    wire [WORD_WIDTH_LONG-1:0]  divisor_loaded;
    reg  [WORD_WIDTH_LONG-1:0]  divisor_initial = WORD_ZERO_LONG;
    reg  [WORD_WIDTH_LONG-1:0]  divisor_next    = WORD_ZERO_LONG;

    always @(*) begin
        divisor_initial = {divisor_long [WORD_WIDTH_LONG-1], divisor_long [WORD_WIDTH_LONG-1:1]};
    end

    Register_Pipeline
    #(
        .WORD_WIDTH     (WORD_WIDTH_LONG),
        .PIPE_DEPTH     (1),
        .RESET_VALUES   (WORD_ZERO_LONG)
    )
    divisor_storage
    (
        .clock          (clock),
        .clock_enable   (divisor_enable),
        .clear          (1'b0),
        .parallel_load  (divisor_load),
        .parallel_in    (divisor_initial),
        // verilator lint_off PINCONNECTEMPTY
        .parallel_out   (),
        // verilator lint_on  PINCONNECTEMPTY
        .pipe_in        (divisor_next),
        .pipe_out       (divisor_loaded)
    );

// Store the remainder increment.

    reg                         remainder_increment_enable  = 1'b0;
    reg                         remainder_increment_load    = 1'b0;
    wire [WORD_WIDTH_LONG-1:0]  remainder_increment_loaded;
    reg  [WORD_WIDTH_LONG-1:0]  remainder_increment_initial = WORD_ZERO_LONG;
    reg  [WORD_WIDTH_LONG-1:0]  remainder_increment_next    = WORD_ZERO_LONG;

    always @(*) begin
        remainder_increment_initial = {divisor_long [0], WORD_ZERO};
    end

    Register_Pipeline
    #(
        .WORD_WIDTH     (WORD_WIDTH_LONG),
        .PIPE_DEPTH     (1),
        .RESET_VALUES   (WORD_ZERO_LONG)
    )
    remainder_increment_storage
    (
        .clock          (clock),
        .clock_enable   (remainder_increment_enable),
        .clear          (1'b0),
        .parallel_load  (remainder_increment_load),
        .parallel_in    (remainder_increment_initial),
        // verilator lint_off PINCONNECTEMPTY
        .parallel_out   (),
        // verilator lint_on  PINCONNECTEMPTY
        .pipe_in        (remainder_increment_next),
        .pipe_out       (remainder_increment_loaded)
    );

//### Dividend and Remainder

    wire [WORD_WIDTH_LONG-1:0] dividend_long;

    Width_Adjuster
    #(
        .WORD_WIDTH_IN  (WORD_WIDTH),
        .SIGNED         (1),
        .WORD_WIDTH_OUT (WORD_WIDTH_LONG)
    )
    dividend_extend
    (
        // It's possible some input bits are truncated away
        // verilator lint_off UNUSED
        .original_input     (dividend),
        // verilator lint_on  UNUSED
        .adjusted_output    (dividend_long)
    );

// Extract the initial sign of the dividend.

    reg  dividend_sign_initial_load = 1'b0;
    wire dividend_sign_initial;

    Register
    #(
        .WORD_WIDTH     (1),
        .RESET_VALUE    (1'b0)
    )
    dividend_sign_initial_storage
    (
        .clock          (clock),
        .clock_enable   (dividend_sign_initial_load),
        .clear          (clear),
        .data_in        (dividend_long [WORD_WIDTH_LONG-1]),
        .data_out       (dividend_sign_initial)
    );

// The dividend (numerator of a fraction) is stored as the remainder of the
// division. We repeatedly add/subtract the remainder_increment unless the
// remainder would become too small and flip its sign.
    
    reg                         remainder_enable = 1'b0;
    reg                         remainder_load   = 1'b0;
    wire [WORD_WIDTH_LONG-1:0]  remainder_loaded;
    wire [WORD_WIDTH_LONG-1:0]  remainder_next;

    Register_Pipeline
    #(
        .WORD_WIDTH     (WORD_WIDTH_LONG),
        .PIPE_DEPTH     (1),
        .RESET_VALUES   (WORD_ZERO_LONG)
    )
    remainder_storage
    (
        .clock          (clock),
        .clock_enable   (remainder_enable),
        .clear          (1'b0),
        .parallel_load  (remainder_load),
        .parallel_in    (dividend_long),
        // verilator lint_off PINCONNECTEMPTY
        .parallel_out   (),
        // verilator lint_on  PINCONNECTEMPTY
        .pipe_in        (remainder_next),
        .pipe_out       (remainder_loaded)
    );

    Width_Adjuster
    #(
        .WORD_WIDTH_IN  (WORD_WIDTH_LONG),
        .SIGNED         (1),
        .WORD_WIDTH_OUT (WORD_WIDTH)
    )
    remainder_shorten
    (
        // It's possible some input bits are truncated away
        // verilator lint_off UNUSED
        .original_input     (remainder_loaded),
        // verilator lint_on  UNUSED
        .adjusted_output    (remainder)
    );

// Now, run all stored data through a pipeline. We expect forward register
// retiming to push the pipeline registers, if any, through the following
// arithmetic and bit-reduction logic to reduce the critical path delay.

    localparam PIPELINE_WIDTH = 1 + WORD_WIDTH_LONG + WORD_WIDTH_LONG + 1 + WORD_WIDTH_LONG;

    wire                        divisor_sign_initial_pipelined;
    wire [WORD_WIDTH_LONG-1:0]  divisor_loaded_pipelined;
    wire [WORD_WIDTH_LONG-1:0]  remainder_increment_loaded_pipelined;
    wire                        dividend_sign_initial_pipelined;
    wire [WORD_WIDTH_LONG-1:0]  remainder_loaded_pipelined;

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
        .pipe_in        ({divisor_sign_initial,           divisor_loaded,           remainder_increment_loaded,           dividend_sign_initial,           remainder_loaded}),
        .pipe_out       ({divisor_sign_initial_pipelined, divisor_loaded_pipelined, remainder_increment_loaded_pipelined, dividend_sign_initial_pipelined, remainder_loaded_pipelined})
    );

    always @(*) begin
        divisor_next    = {divisor_loaded_pipelined [WORD_WIDTH_LONG-1], divisor_loaded_pipelined [WORD_WIDTH_LONG-1:1]};
    end

    always @(*) begin
        remainder_increment_next = {divisor_loaded_pipelined [0], remainder_increment_loaded_pipelined [WORD_WIDTH_LONG-1:1]};
    end

// Now, depending on the divisor sign, check the contents of divisor to see if
// there are still non-sign bits in it, which means the remainder_increment is
// invalid, and check if the sign of the remainder_increment does not match the sign
// of the divisor, which means we haven't yet shifted enough bits into the
// remainder_increment to make it a valid number.

    reg remainder_increment_sign  = 1'b0;
    reg divisor_all_sign_bits     = 1'b0;
    reg remainder_increment_valid = 1'b0;

    always @(*) begin
        remainder_increment_sign  = remainder_increment_loaded_pipelined [WORD_WIDTH_LONG-1];
        divisor_all_sign_bits    = (divisor_sign_initial_pipelined == POSITIVE) ? (divisor_loaded_pipelined == WORD_ZERO_LONG) : (divisor_loaded_pipelined == WORD_ONES_LONG);
        remainder_increment_valid = (remainder_increment_sign == divisor_sign_initial_pipelined) && (divisor_all_sign_bits == 1'b1);
    end

// Then apply the remainder_increment to the remainder

    reg remainder_add_sub = 1'b0;

    always @(*) begin
        remainder_add_sub = (divisor_sign_initial_pipelined == dividend_sign_initial_pipelined) ? SUB : ADD;
    end

    wire remainder_next_overflow;

    Adder_Subtractor_Binary
    #(
        .WORD_WIDTH (WORD_WIDTH_LONG)
    )
    remainder_calc
    (
        .add_sub    (remainder_add_sub), // 0/1 -> A+B/A-B
        .carry_in   (1'b0),
        .A          (remainder_loaded_pipelined),
        .B          (remainder_increment_loaded_pipelined),
        .sum        (remainder_next),
        // verilator lint_off PINCONNECTEMPTY
        .carry_out  (),
        .carries    (),
        // verilator lint_on  PINCONNECTEMPTY
        .overflow   (remainder_next_overflow)
    );

// If the next division step would overshoot past zero and change the sign of
// the remainder, meaning too much was added/subtracted, then this division
// step does nothing.

    reg remainder_next_valid = 1'b0;

    always @(*) begin
        remainder_next_valid = ((remainder_next [WORD_WIDTH_LONG-1] == dividend_sign_initial_pipelined) && (remainder_next_overflow == 1'b0)) || (remainder_next == WORD_ZERO_LONG);
    end

// And report if we tried to divide by zero. We do this after the pipeline
// since it's a reduction operation. We can load this at the end of the first
// set of pipeline steps (so calculation_steps == STEPS_INITIAL and
// pipeline_steps == STEPS_ZERO).

// We have to reconstruct the initially loaded divisor by undoing the first
// shift into the remainder increment at load time.

    reg divisor_is_zero     = 1'b0;
    reg divide_by_zero_load = 1'b0;

    always @(*) begin
        divisor_is_zero = ({divisor_loaded_pipelined [0 +: WORD_WIDTH], remainder_increment_loaded_pipelined [WORD_WIDTH_LONG-1]} == WORD_ZERO_LONG);
    end

    Register
    #(
        .WORD_WIDTH     (1),
        .RESET_VALUE    (1'b0)
    )
    divide_by_zero_storage
    (
        .clock          (clock),
        .clock_enable   (divide_by_zero_load),
        .clear          (clear),
        .data_in        (divisor_is_zero),
        .data_out       (divide_by_zero)
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
        control_valid  = (state == STATE_CALC) && (pipeline_step == PIPELINE_STEPS_ZERO);
    end

// Then, define the basic interactions with and transformations within this
// module.  Past this point, we should not refer directly to the FSM states,
// but to these events which are combinations of states and signals.

    reg load_inputs       = 1'b0; // When we load the dividend and divisor.
    reg read_outputs      = 1'b0; // When we read out the remainder.
    reg read_control      = 1'b0; // When other computations acknowledge the calculation step.
    reg calculating       = 1'b0; // High while performing the division steps.
    reg step_done         = 1'b0; // High when a calculation exits the pipeline and is ack'ed by other computations.
    reg first_calculation = 1'b0; // High during the first calculation step.
    reg last_calculation  = 1'b0; // High during the last calculation step.

    always @(*) begin
        load_inputs       = (input_ready   == 1'b1) && (input_valid   == 1'b1);
        read_outputs      = (output_valid  == 1'b1) && (output_ready  == 1'b1);
        read_control      = (control_valid == 1'b1) && (control_ready == 1'b1);
        calculating       = (state == STATE_CALC);
        step_done         = (read_control == 1'b1);
        first_calculation = (read_control == 1'b1) && (calculation_step == STEPS_INITIAL [STEPS_WIDTH-1:0]);
        last_calculation  = (read_control == 1'b1) && (calculation_step == STEPS_ZERO);
    end

// Define the running state machine transitions. There is no handling of erroneous states.

    always @(*) begin
        state_next = (load_inputs       == 1'b1) ? STATE_CALC : state;
        state_next = (last_calculation  == 1'b1) ? STATE_DONE : state_next;
        state_next = (read_outputs      == 1'b1) ? STATE_LOAD : state_next;
    end

// Is the current division step valid?

    always @(*) begin
        step_ok = (remainder_next_valid == 1'b1) && (remainder_increment_valid == 1'b1) && (calculating == 1'b1) && (step_done == 1'b1);
    end

// Control the calculation step counter

    always @(*) begin
        calculation_step_clear = (load_inputs == 1'b1) || (clear == 1'b1);
        calculation_step_do    = (step_done   == 1'b1);
    end

// Control the pipeline step counter

    always @(*) begin
        pipeline_step_clear = (step_done   == 1'b1) || (clear == 1'b1);
        pipeline_step_do    = (calculating == 1'b1);
    end

// Control the divisor and remainder increment.

    always @(*) begin
        divide_by_zero_load         = (first_calculation == 1'b1);
        divisor_load                = (load_inputs    == 1'b1);
        divisor_enable              = (load_inputs    == 1'b1) || ((calculating == 1'b1) && (step_done == 1'b1));
        divisor_sign_initial_load   = (load_inputs    == 1'b1);
        remainder_increment_load    = (divisor_load   == 1'b1);
        remainder_increment_enable  = (divisor_enable == 1'b1);
    end

// Control the dividend and the remainder.

    always @(*) begin
        dividend_sign_initial_load  = (load_inputs == 1'b1);
        remainder_load              = (load_inputs == 1'b1);
        remainder_enable            = (load_inputs == 1'b1) || ((step_ok == 1'b1) && (step_done == 1'b1));
    end

endmodule 

