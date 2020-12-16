
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

// The implementation refines this approach by using multiples of the
// divisor, as in manual long division. Imagine aligning the LSB of the
// divisor to the MSB of the (sign-extended) dividend and performing the
// addition or subtraction. If the operation result has the opposite sign,
// then the divisor is too big, so we shift the dividend right by 1 bit and
// try again. Thus, it takes WORD_WIDTH steps to try all possible divisor
// multiples. 

// In hardware, we do this by initializing the remainder with the
// sign-extension (0 or -1) of the dividend, then by shifting the dividend
// bit-by-bit, MSB-first, into the remainder LSB then adding/subtracting the
// divisor from the remainder. We update the new remainder result if
// the sign did not flip (meaning the shifted bits of the dividend were large
// enough). Whatever is left at the end of the calculation is the remainder,
// with the correct sign.

// Most importantly, we send out a "step_ok" signal through another
// ready/valid handshake to allow other logic to follow along and only update
// themselves when the divisor multiple could be successfully added/removed
// from the remainder. The ready/valid handshake itself tells the remote logic
// to do a calculation, and reports when it is done.

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
    output reg  [WORD_WIDTH-1:0]    remainder,
    output reg                      divide_by_zero,
    
    output reg                      control_valid,
    input  wire                     control_ready,
    output reg                      add_sub,
    output reg                      last_calculation
);

    `include "clog2_function.vh"

    localparam WORD_ZERO = {WORD_WIDTH{1'b0}};

    initial begin
        input_ready      = 1'b0;
        output_valid     = 1'b0;
        remainder        = WORD_ZERO;
        divide_by_zero   = 1'b0;
        control_valid    = 1'b0;
        add_sub          = 1'b0;
        last_calculation = 1'b0;
    end

// We need one extra bit in the remainder since the shift left always happens,
// so the final result is shifted by one and we don't want to lose the MSB.
// The correct subsets of this wider register are extracted further down.

    localparam REMAINDER_WIDTH = WORD_WIDTH + 1;
    localparam REMAINDER_ZERO  = {REMAINDER_WIDTH{1'b0}}; 

// Let's encode the operation convention, to avoid typos.

    localparam ADD = 1'b0;
    localparam SUB = 1'b1;

//## Data Path

// Store the divisor and extract whether it is zero. These never
// change during division.

    reg                     divisor_enable = 1'b0;
    wire [WORD_WIDTH-1:0]   divisor_loaded;

    Register
    #(
        .WORD_WIDTH     (WORD_WIDTH),
        .RESET_VALUE    (WORD_ZERO)
    )
    divisor_storage
    (
        .clock          (clock),
        .clock_enable   (divisor_enable),
        .clear          (1'b0),
        .data_in        (divisor),
        .data_out       (divisor_loaded)
    );

// Store the dividend and shift it left at each calculation step. We load the
// dividend value shifted left by 1 during the load cycle as the next cycle is
// the first cycle of calculation, and we need all the data ready.
    
    reg                     dividend_enable = 1'b0;
    reg                     dividend_load   = 1'b0;
    wire [WORD_WIDTH-1:0]   dividend_loaded;
    reg  [WORD_WIDTH-1:0]   dividend_next   = WORD_ZERO;

    Register_Pipeline
    #(
        .WORD_WIDTH     (WORD_WIDTH),
        .PIPE_DEPTH     (1),
        .RESET_VALUES   (WORD_ZERO)
    )
    dividend_storage
    (
        .clock          (clock),
        .clock_enable   (dividend_enable),
        .clear          (1'b0),
        .parallel_load  (dividend_load),
        .parallel_in    (dividend << 1),
        // verilator lint_off PINCONNECTEMPTY
        .parallel_out   (),
        // verilator lint_on  PINCONNECTEMPTY
        .pipe_in        (dividend_next),
        .pipe_out       (dividend_loaded)
    );

// Store the remainder. Initialized with a zero or -1 as a sign-extension of
// the initial MSB of the dividend at load time.  At each calculation step,
// gets loaded with the new remainder left-shifted by 1 with the LSB filled-in
// with the current MSB of the dividend.

// Must be 1 bit wider than the dividend, since the left-shift always happens
// and we don't want to lose the MSB on the last step. This means we use the
// last `WORD_WIDTH` bits as the remainder output, and the first `WORD_WIDTH`
// bits for the new remainder calculations.

    reg                         dividend_sign_at_load   = 1'b0;
    reg [REMAINDER_WIDTH-1:0]   remainder_initial       = REMAINDER_ZERO;

    always @(*) begin
        dividend_sign_at_load = dividend [WORD_WIDTH-1];
        remainder_initial     = {REMAINDER_WIDTH{dividend_sign_at_load}};
    end

    reg                         remainder_enable    = 1'b0;
    reg                         remainder_load      = 1'b0;
    reg  [REMAINDER_WIDTH-1:0]  remainder_next      = REMAINDER_ZERO;
    wire [REMAINDER_WIDTH-1:0]  remainder_loaded;

    Register_Pipeline
    #(
        .WORD_WIDTH     (REMAINDER_WIDTH),
        .PIPE_DEPTH     (1),
        .RESET_VALUES   (REMAINDER_ZERO)
    )
    remainder_storage
    (
        .clock          (clock),
        .clock_enable   (remainder_enable),
        .clear          (1'b0),
        .parallel_load  (remainder_load),
        .parallel_in    (remainder_initial),
        // verilator lint_off PINCONNECTEMPTY
        .parallel_out   (),
        // verilator lint_on  PINCONNECTEMPTY
        .pipe_in        (remainder_next),
        .pipe_out       (remainder_loaded)
    );

    always @(*) begin
        remainder = remainder_loaded [1 +: WORD_WIDTH];
    end

// Now, run all stored data through a pipeline. We expect forward register
// retiming to push the pipeline registers, if any, through the following
// arithmetic and bit-reduction logic to reduce the critical path delay.

    localparam PIPELINE_WIDTH = WORD_WIDTH + REMAINDER_WIDTH + WORD_WIDTH;

    wire [WORD_WIDTH-1:0]       dividend_loaded_pipelined;
    wire [REMAINDER_WIDTH-1:0]  remainder_loaded_pipelined;
    wire [WORD_WIDTH-1:0]       divisor_loaded_pipelined;

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
        .pipe_in        ({dividend_loaded,           remainder_loaded,           divisor_loaded}),
        .pipe_out       ({dividend_loaded_pipelined, remainder_loaded_pipelined, divisor_loaded_pipelined})
    );

    reg [WORD_WIDTH-1:0] remainder_calc_pipelined   = WORD_ZERO;
    //reg [WORD_WIDTH-1:0] remainder_output_pipelined = WORD_ZERO;

    always @(*) begin
        remainder_calc_pipelined   = remainder_loaded_pipelined [0 +: WORD_WIDTH];
        //remainder_output_pipelined = remainder_loaded_pipelined [1 +: WORD_WIDTH];
    end

// Compute the new remainder: remainder_new = remainder_calc +/- divisor.

    reg divisor_loaded_pipelined_sign = 1'b0;
    reg remainder_calc_pipelined_sign = 1'b0;
    reg remainder_add_sub             = ADD;

    always @(*) begin
        divisor_loaded_pipelined_sign = divisor_loaded_pipelined [WORD_WIDTH-1];
        remainder_calc_pipelined_sign = remainder_calc_pipelined [WORD_WIDTH-1];
        remainder_add_sub = (remainder_calc_pipelined_sign == divisor_loaded_pipelined_sign) ? SUB : ADD;
    end

    wire [WORD_WIDTH-1:0] remainder_new;

    Adder_Subtractor_Binary
    #(
        .WORD_WIDTH     (WORD_WIDTH)
    )
    remainder_new_calc
    (
        .add_sub    (remainder_add_sub),   // 0/1 -> A+B/A-B
        .carry_in   (1'b0),
        .A          (remainder_calc_pipelined),
        .B          (divisor_loaded_pipelined),
        .sum        (remainder_new),
        // verilator lint_off PINCONNECTEMPTY
        .carry_out      (),
        .carries        (),
        .overflow       ()
        // verilator lint_on  PINCONNECTEMPTY
    );

    reg dividend_msb        = 1'b0;
    reg remainder_new_sign  = 1'b0;

    always @(*) begin
        dividend_msb       = dividend_loaded_pipelined [WORD_WIDTH-1];
        remainder_new_sign = remainder_new [WORD_WIDTH-1];
        remainder_next     = (remainder_new_sign == remainder_calc_pipelined_sign) || (remainder_new == WORD_ZERO) ? {remainder_new, dividend_msb} : {remainder_calc_pipelined, dividend_msb};
    end

// When the dividend is all zero, then we have used up all the information in
// it, and the current division step is the last one, giving us the final
// remainder.

    always @(*) begin
        dividend_next  = (dividend_loaded_pipelined << 1);
    end

    always @(*) begin
        divide_by_zero = (divisor_loaded_pipelined == WORD_ZERO);
    end

//## Control Path

// Each calculation takes `WORD_WIDTH` steps, from `WORD_WIDTH-1` to `0`, plus
// one step to initially load the dividend and divisor. Thus, we need
// a counter of the correct width.

    localparam STEPS_WIDTH      = clog2(WORD_WIDTH);
    localparam STEPS_INITIAL    = WORD_WIDTH - 1;
    localparam STEPS_ZERO       = {STEPS_WIDTH{1'b0}};
    localparam STEPS_ONE        = {{STEPS_WIDTH-1{1'b0}},1'b1};

// We need a pipelining counter so we save the result of a division step only
// once the calculation has propagated through the whole pipeline.  Since the
// pipeline depth can be zero, we have to do some contortions to avoid
// clog2(0) and replications of length zero (which are not legal outside of
// a larger concatenation).

    localparam PIPELINE_STEPS_WIDTH   = (PIPELINE_STAGES <  2) ? 1 : clog2(PIPELINE_STAGES);
    localparam PIPELINE_STEPS_INITIAL = (PIPELINE_STAGES == 0) ? 0 : PIPELINE_STAGES - 1;
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
        calculation_step_clear = (load_inputs == 1'b1);
        calculation_step_do    = (step_done   == 1'b1);
    end

// Control the pipeline step counter

    always @(*) begin
        pipeline_step_clear = (step_done   == 1'b1);
        pipeline_step_do    = (calculating == 1'b1);
    end

// Control the divisor and dividend storage

    always @(*) begin
        divisor_enable       = (load_inputs == 1'b1);
        dividend_enable      = (load_inputs == 1'b1) || (step_done == 1'b1);
        dividend_load        = (load_inputs == 1'b1);
    end

// Control the remainder storage

    always @(*) begin
        remainder_enable = (load_inputs == 1'b1) || (step_done == 1'b1);
        remainder_load   = (load_inputs == 1'b1);
    end

endmodule 

