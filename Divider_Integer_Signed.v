
//# Signed Integer Divider (Truncating Long Division)

// Computes the signed quotient and remainder of the signed dividend and
// divisor, using truncating long division, which matches the behaviour of
// most programming languages and manual long division. For example, here are
// the expected values:

// *  22 /   7 =  3 rem  1
// * -22 /   7 = -3 rem -1
// *  22 /  -7 = -3 rem  1
// * -22 /  -7 =  3 rem -1
// *   7 /  22 =  0 rem  7
// *  -7 / -22 =  0 rem -7
// *  -7 /  22 =  0 rem -7
// *   7 / -22 =  0 rem  7
// *   0 /   0 = -1 rem  0 (raises divide_by_zero)
// *  22 /   0 = -1 rem 22 (raises divide_by_zero)
// * -22 /   0 =  1 rem 22 (raises divide_by_zero)

`default_nettype none

module Divider_Integer_Signed
#(
    parameter WORD_WIDTH        = 8,
    parameter PIPELINE_STAGES   = 2
)
(
    input  wire                         clock,
    input  wire                         clear,

    input  wire                         in_valid,
    output reg                          in_ready,
    input  wire     [WORD_WIDTH-1:0]    dividend,
    input  wire     [WORD_WIDTH-1:0]    divisor,

    output reg                          out_valid,
    input  wire                         out_ready,
    output wire     [WORD_WIDTH-1:0]    quotient,
    output wire     [WORD_WIDTH-1:0]    remainder,
    output wire                         divide_by_zero
);

//## Initialization and Constants

// Begin with handshake ports idle.

    initial begin
        in_ready        = 1'b0;
        out_valid       = 1'b0;
    end

// Define constants to keep the intent clear.

    localparam WORD_ZERO        = {WORD_WIDTH{1'b0}};
    localparam WORD_ONE         = {{WORD_WIDTH-1{1'b0}},1'b1};
    localparam WORD_ONES        = {WORD_WIDTH{1'b1}};

// We have to internally compute with one extra bit of range to allow the
// minimum signed number to be expressible as an unsigned number. Else, we
// cannot subtract any multiple of itself from it (e.g. -8/1 needs to add +8
// to the remainder to reach "1 rem 0", and with the minimum number of bits
// (4), we can only represent up to +7)

    localparam WORD_WIDTH_LONG  = WORD_WIDTH + 1;

    localparam WORD_ZERO_LONG   = {WORD_WIDTH_LONG{1'b0}};
    localparam WORD_ONE_LONG    = {{WORD_WIDTH_LONG-1{1'b0}},1'b1};
    localparam WORD_ONES_LONG   = {WORD_WIDTH_LONG{1'b1}};

// For the register pipelines

    localparam WORD_WIDTH_PIPE = WORD_WIDTH_LONG * PIPELINE_STAGES;
    localparam WORD_ZERO_PIPE  = {WORD_WIDTH_PIPE{1'b0}};

// Misc.

    localparam ADD              = 1'b0;
    localparam SUB              = 1'b1;
    localparam POSITIVE         = 1'b0;
    localparam NEGATIVE         = 1'b1;

// Each division takes (WORD_WIDTH*PIPELINE_STAGES)+2 steps: 1 load, then
// WORD_WIDTH_LONG division steps, each taking PIPELINE_STAGES cycles, and one
// cycle to read out. So we set up a counter which goes from WORD_WIDTH_LONG-1
// to zero. The PIPELINE_STAGES will be tracked with a simple pulse delay.

    `include "clog2_function.vh"

    localparam STEPS_WIDTH      = clog2(WORD_WIDTH_LONG);
    localparam STEPS_INITIAL    = WORD_WIDTH_LONG - 1;
    localparam STEPS_ZERO       = {STEPS_WIDTH{1'b0}};
    localparam STEPS_ONE        = {{STEPS_WIDTH-1{1'b0}},1'b1};

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

// Extract the initial sign of the divisor.

    reg  divisor_msb        = 1'b0;
    reg  divisor_sign_load  = 1'b0;
    wire divisor_sign;

    always @(*) begin
        divisor_msb = divisor_long [WORD_WIDTH_LONG-1];
    end

    Register
    #(
        .WORD_WIDTH     (1),
        .RESET_VALUE    (1'b0)
    )
    divisor_sign_storage
    (
        .clock          (clock),
        .clock_enable   (divisor_sign_load),
        .clear          (1'b0),
        .data_in        (divisor_msb),
        .data_out       (divisor_sign)
    );

// And report if we tried to divide by zero. Unlike the quotient/remainder,
// this signal is always immediately valid.

    reg divisor_is_zero     = 1'b0;
    reg divide_by_zero_load = 1'b0;

    always @(*) begin
        divisor_is_zero = (divisor_long == WORD_ZERO_LONG);
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
        .clear          (1'b0),
        .data_in        (divisor_is_zero),
        .data_out       (divide_by_zero)
    );

// Store the divisor aside and shift its LSB into the MSB of the
// remainder_increment at each division step. The initial load does the first
// shift implicitly.

    reg                         divisor_enable = 1'b0;
    reg                         divisor_load   = 1'b0;
    reg  [WORD_WIDTH_LONG-1:0]  divisor_selected = WORD_ZERO_LONG;
    wire [WORD_WIDTH_LONG-1:0]  divisor_shifted;

    Register
    #(
        .WORD_WIDTH     (WORD_WIDTH_LONG),
        .RESET_VALUE    (WORD_ZERO_LONG)
    )
    divisor_storage
    (
        .clock          (clock),
        .clock_enable   (divisor_enable),
        .clear          (1'b0),
        .data_in        (divisor_selected),
        .data_out       (divisor_shifted)
    );

    always @(*) begin
        divisor_selected = (divisor_load == 1'b1) ? {divisor_msb, divisor_long [WORD_WIDTH_LONG-1:1]} : {divisor_shifted [WORD_WIDTH_LONG-1], divisor_shifted [WORD_WIDTH_LONG-1:1]};
    end

// Remainder Increment

    reg                         remainder_increment_load        = 1'b0;
    reg                         remainder_increment_enable      = 1'b0;
    reg  [WORD_WIDTH_LONG-1:0]  remainder_increment_selected    = WORD_ZERO_LONG;
    wire [WORD_WIDTH_LONG-1:0]  remainder_increment;

    Register
    #(
        .WORD_WIDTH     (WORD_WIDTH_LONG),
        .RESET_VALUE    (WORD_ZERO_LONG)
    )
    remainder_increment_storage
    (
        .clock          (clock),
        .clock_enable   (remainder_increment_enable),
        .clear          (1'b0),
        .data_in        (remainder_increment_selected),
        .data_out       (remainder_increment)
    );

    always @(*) begin
        remainder_increment_selected = (remainder_increment_load == 1'b1) ? {divisor_long [0], WORD_ZERO} : {divisor_shifted [0], remainder_increment [WORD_WIDTH_LONG-1:1]};
    end

// Let's pipeline this, to see...

    reg remainder_increment_sign  = 1'b0;

    always @(*) begin
        remainder_increment_sign  = remainder_increment [WORD_WIDTH_LONG-1];
    end

    localparam DIV_REM_PIPE_WIDTH = WORD_WIDTH_LONG + 1;
    localparam DIV_REM_PIPE_ZERO  = {DIV_REM_PIPE_WIDTH*PIPELINE_STAGES{1'b0}};

    wire [WORD_WIDTH_LONG-1:0] divisor_shifted_pipelined;
    wire                       remainder_increment_sign_pipelined;

    Register_Pipeline
    #(
        .WORD_WIDTH     (DIV_REM_PIPE_WIDTH),
        .PIPE_DEPTH     (PIPELINE_STAGES),
        // concatenation of each stage initial/reset value
        .RESET_VALUES   (DIV_REM_PIPE_ZERO)
    )
    instance_name
    (
        .clock          (clock),
        .clock_enable   (1'b1),
        .clear          (1'b0),
        .parallel_load  (1'b0),
        .parallel_in    (DIV_REM_PIPE_ZERO),
        // verilator lint_off PINCONNECTEMPTY
        .parallel_out   (),
        // verilator lint_on  PINCONNECTEMPTY
        .pipe_in        ({divisor_shifted,           remainder_increment_sign}),
        .pipe_out       ({divisor_shifted_pipelined, remainder_increment_sign_pipelined})
    );

// Now, depending on the divisor sign, check the contents of divisor to see if
// there are still non-sign bits in it, which means the remainder_increment is
// invalid, and if the sign of the remainder_increment does not match the sign
// of the divisor, which means we haven't yet shifted enough bits into the
// remainder_increment to make it a valid number.

    reg divisor_all_sign_bits     = 1'b0;
    reg remainder_increment_valid = 1'b0;

    always @(*) begin
        divisor_all_sign_bits    = (divisor_sign == POSITIVE) ? (divisor_shifted_pipelined == WORD_ZERO_LONG) : (divisor_shifted_pipelined == WORD_ONES_LONG);
        remainder_increment_valid = (remainder_increment_sign_pipelined == divisor_sign) && (divisor_all_sign_bits == 1'b1);
    end

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

    reg  dividend_sign_load = 1'b0;
    wire dividend_sign;

    Register
    #(
        .WORD_WIDTH     (1),
        .RESET_VALUE    (1'b0)
    )
    dividend_sign_storage
    (
        .clock          (clock),
        .clock_enable   (dividend_sign_load),
        .clear          (1'b0),
        .data_in        (dividend_long [WORD_WIDTH_LONG-1]),
        .data_out       (dividend_sign)
    );

// The dividend (numerator of a fraction) is used as the remainder of the
// division. We repeatedly add/subtract the remainder_increment unless the
// remainder would become too small and flip its sign.

    reg                         remainder_enable    = 1'b0;
    reg  [WORD_WIDTH_LONG-1:0]  remainder_selected  = WORD_ZERO_LONG;
    wire [WORD_WIDTH_LONG-1:0]  remainder_long;

    Register
    #(
        .WORD_WIDTH     (WORD_WIDTH_LONG),
        .RESET_VALUE    (WORD_ZERO_LONG)
    )
    remainder_storage
    (
        .clock          (clock),
        .clock_enable   (remainder_enable),
        .clear          (1'b0),
        .data_in        (remainder_selected),
        .data_out       (remainder_long)
    );

    wire [WORD_WIDTH_LONG-1:0]  remainder_next;
    reg                         remainder_load = 1'b0;

    always @(*) begin
        remainder_selected = (remainder_load == 1'b1) ? dividend_long : remainder_next;    
    end

// Decide how we compute the remainder_next

    reg remainder_add_sub = 1'b0;

    always @(*) begin
        remainder_add_sub = (divisor_sign != dividend_sign) ? ADD : SUB;
    end

// Pipeline the inputs to the Adder_Subtractor_Binary. We expect these
// registers to forward-retime into the adder logic at least. Calculating
// remainder_next and making decisions based on its value is the main critical
// path of the whole design. 

// Also carry a pulse along the pipeline to signal
// when a calculation starts and ends.

    localparam PIPE_WIDTH_REMAINDER = 1 + WORD_WIDTH_LONG + WORD_WIDTH_LONG;
    localparam PIPE_WIDTH_REMAINDER_ZERO = {PIPE_WIDTH_REMAINDER*PIPELINE_STAGES{1'b0}};

    wire                        remainder_add_sub_pipelined;
    wire [WORD_WIDTH_LONG-1:0]  remainder_long_pipelined;
    wire [WORD_WIDTH_LONG-1:0]  remainder_increment_pipelined;

    Register_Pipeline
    #(
        .WORD_WIDTH     (PIPE_WIDTH_REMAINDER),
        .PIPE_DEPTH     (PIPELINE_STAGES),
        // concatenation of each stage initial/reset value
        .RESET_VALUES   (PIPE_WIDTH_REMAINDER_ZERO)
    )
    remainder_calc_pipeline
    (
        .clock          (clock),
        .clock_enable   (1'b1),
        .clear          (1'b0),
        .parallel_load  (1'b0),
        .parallel_in    (PIPE_WIDTH_REMAINDER_ZERO),
        // verilator lint_off PINCONNECTEMPTY
        .parallel_out   (),
        // verilator lint_on  PINCONNECTEMPTY
        .pipe_in        ({remainder_add_sub,           remainder_long,           remainder_increment}),
        .pipe_out       ({remainder_add_sub_pipelined, remainder_long_pipelined, remainder_increment_pipelined})
    );

    localparam PIPELINE_STAGES_CALC         = PIPELINE_STAGES + 1;
    localparam PIPELINE_STAGES_CALC_ZERO    = {PIPELINE_STAGES_CALC{1'b0}};

    reg                         remainder_calc_start = 1'b0;
    wire                        remainder_calc_end;

    Register_Pipeline
    #(
        .WORD_WIDTH     (1),
        .PIPE_DEPTH     (PIPELINE_STAGES_CALC),
        // concatenation of each stage initial/reset value
        .RESET_VALUES   (PIPELINE_STAGES_CALC_ZERO)
    )
    calc_pipeline
    (
        .clock          (clock),
        .clock_enable   (1'b1),
        .clear          (1'b0),
        .parallel_load  (1'b0),
        .parallel_in    (PIPELINE_STAGES_CALC_ZERO),
        // verilator lint_off PINCONNECTEMPTY
        .parallel_out   (),
        // verilator lint_on  PINCONNECTEMPTY
        .pipe_in        (remainder_calc_start),
        .pipe_out       (remainder_calc_end)
    );

// Then apply the remainder_increment

    Adder_Subtractor_Binary
    #(
        .WORD_WIDTH (WORD_WIDTH_LONG)
    )
    remainder_calc
    (
        .add_sub    (remainder_add_sub_pipelined), // 0/1 -> A+B/A-B
        .carry_in   (1'b0),
        .A          (remainder_long_pipelined),
        .B          (remainder_increment_pipelined),
        .sum        (remainder_next),
        // verilator lint_off PINCONNECTEMPTY
        .carry_out  (),
        .carries    (),
        .overflow   ()
        // verilator lint_on  PINCONNECTEMPTY
    );

// If the next division step would overshoot past zero and change the sign of
// the remainder, meaning too much was added/subtracted, then this division
// step does nothing. Landing on zero is the special case when the remainder
// starts negative.

    reg remainder_overshoot = 1'b0;

    always @(*) begin
        remainder_overshoot = (dividend_sign != remainder_next [WORD_WIDTH_LONG-1]) && (remainder_next != WORD_ZERO_LONG);
    end

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
        .original_input     (remainder_long),
        // verilator lint_on  UNUSED
        .adjusted_output    (remainder)
    );


//### Quotient Increment

// The quotient increment which is added/subtracted to/from the quotient each
// time we could remove the divisor from the remainder.  Shift it right by
// 1 each calculation step, so we increment by decreasing multiples of 2 at
// each division step.

    reg                         quotient_increment_enable   = 1'b0;
    reg                         quotient_increment_load     = 1'b0;
    wire [WORD_WIDTH_LONG-1:0]  quotient_increment_reversed;
    wire [WORD_WIDTH_LONG-1:0]  quotient_increment;

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
        .clear          (1'b0),
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

// Accumulate the quotient_increment into the quotient at each valid division
// step.

    reg quotient_add_sub    = 1'b0;

    always @(*) begin
        quotient_add_sub = (divisor_sign != dividend_sign) ? SUB : ADD;
    end

    reg                         quotient_enable = 1'b0;
    reg  [WORD_WIDTH_LONG-1:0]  quotient_selected = WORD_ZERO_LONG;
    wire [WORD_WIDTH_LONG-1:0]  quotient_long;

    Register
    #(
        .WORD_WIDTH     (WORD_WIDTH_LONG),
        .RESET_VALUE    (WORD_ZERO_LONG)
    )
    quotient_storage
    (
        .clock          (clock),
        .clock_enable   (quotient_enable),
        .clear          (1'b0),
        .data_in        (quotient_selected),
        .data_out       (quotient_long)
    );

    reg                         quotient_load = 1'b0;
    wire [WORD_WIDTH_LONG-1:0]  quotient_next;

    always @(*) begin
        quotient_selected = (quotient_load == 1'b1) ? WORD_ZERO_LONG : quotient_next;    
    end

// Pipeline the inputs to the Adder_Subtractor_Binary. We expect these
// registers to forward-retime into the adder logic at least. 

    localparam PIPE_WIDTH_QUOTIENT      = 1 + WORD_WIDTH_LONG + WORD_WIDTH_LONG;
    localparam PIPE_WIDTH_QUOTIENT_ZERO = {PIPE_WIDTH_QUOTIENT*PIPELINE_STAGES{1'b0}};

    wire                        quotient_add_sub_pipelined;
    wire [WORD_WIDTH_LONG-1:0]  quotient_long_pipelined;
    wire [WORD_WIDTH_LONG-1:0]  quotient_increment_pipelined;

    Register_Pipeline
    #(
        .WORD_WIDTH     (PIPE_WIDTH_QUOTIENT),
        .PIPE_DEPTH     (PIPELINE_STAGES),
        // concatenation of each stage initial/reset value
        .RESET_VALUES   (PIPE_WIDTH_QUOTIENT_ZERO)
    )
    quotient_calc_pipeline
    (
        .clock          (clock),
        .clock_enable   (1'b1),
        .clear          (1'b0),
        .parallel_load  (1'b0),
        .parallel_in    (PIPE_WIDTH_QUOTIENT_ZERO),
        // verilator lint_off PINCONNECTEMPTY
        .parallel_out   (),
        // verilator lint_on  PINCONNECTEMPTY
        .pipe_in        ({quotient_add_sub,           quotient_long,           quotient_increment}),
        .pipe_out       ({quotient_add_sub_pipelined, quotient_long_pipelined, quotient_increment_pipelined})
    );

// Then apply the quotient_increment

    Adder_Subtractor_Binary
    #(
        .WORD_WIDTH (WORD_WIDTH_LONG)
    )
    quotient_calc
    (
        .add_sub    (quotient_add_sub_pipelined), // 0/1 -> A+B/A-B
        .carry_in   (1'b0),
        .A          (quotient_long_pipelined),
        .B          (quotient_increment_pipelined),
        .sum        (quotient_next),
        // verilator lint_off PINCONNECTEMPTY
        .carry_out  (),
        .carries    (),
        .overflow   ()
        // verilator lint_on  PINCONNECTEMPTY
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
        .original_input     (quotient_long),
        // verilator lint_on  UNUSED
        .adjusted_output    (quotient)
    );


//## Control Path

//### States

// We denote state as two bits, with the following transitions: `LOAD -> CALC
// -> DONE -> LOAD`. We don't handle the fourth, impossible case.

    localparam                      STATE_WIDTH     = 2;
    localparam [STATE_WIDTH-1:0]    STATE_LOAD      = 'b00;
    localparam [STATE_WIDTH-1:0]    STATE_CALC      = 'b01;
    localparam [STATE_WIDTH-1:0]    STATE_DONE      = 'b10;
    localparam [STATE_WIDTH-1:0]    STATE_ERROR     = 'b11; // Never reached.

// The running state bits, from which we derive the control outputs and the
// internal control signals.

    reg  [STATE_WIDTH-1:0]  next_state  = STATE_LOAD;
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
        .data_in        (next_state),
        .data_out       (state)
    );

// Count down WORD_WIDTH-1 calculation steps for the entire division. Stops at
// zero, and reloads when leaving STATE_LOAD.

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

// First, the input and output handshakes. To avoid long combination paths,
// ready and valid should not depend directly on eachother.

// Accept inputs when empty (after results are read out or frehsly
// reset/cleared). Declare outputs valid when calculation is done.

    always @(*) begin
        out_valid   = (state == STATE_DONE);
        in_ready    = (state == STATE_LOAD);
    end

// Then, define the basic interactions with and transformations within this
// module.  Past this point, we should not refer directly to the FSM states,
// but to these events which are combinations of states and signals.

    reg load_inputs       = 1'b0; // When we write in the initial values.
    reg read_outputs      = 1'b0; // When we read out the results.
    reg calculating       = 1'b0; // High while performing the division steps.
    reg last_calculation  = 1'b0; // High during the last calculation step.

    always @(*) begin
        load_inputs       = (in_ready  == 1'b1) && (in_valid  == 1'b1);
        read_outputs      = (out_valid == 1'b1) && (out_ready == 1'b1);
        calculating       = (state == STATE_CALC);
        last_calculation  = (state == STATE_CALC) && (calculation_step == STEPS_ZERO) && (remainder_calc_end == 1'b1);
    end

// Define the running state machine transitions. There is no handling of erroneous states.

    always @(*) begin
        next_state  = (load_inputs      == 1'b1) ? STATE_CALC : state;
        next_state  = (last_calculation == 1'b1) ? STATE_DONE : next_state;
        next_state  = (read_outputs     == 1'b1) ? STATE_LOAD : next_state;
    end

// Is the current division step valid?

    reg calculation_step_valid = 1'b0;

    always @(*) begin
        calculation_step_valid = (remainder_overshoot == 1'b0) && (remainder_increment_valid == 1'b1) && (remainder_calc_end == 1'b1);
    end

// Start and stop the pipelined calculations by sending/blocking a pulse that
// circulates along the pipeline until the last division step.

    wire division_step_pulse;

    Pulse_Generator
    division_step
    (
        .clock              (clock),
        .level_in           (calculating),
        .pulse_posedge_out  (division_step_pulse),
        // verilator lint_off PINCONNECTEMPTY
        .pulse_negedge_out  (),
        .pulse_anyedge_out  ()
        // verilator lint_on  PINCONNECTEMPTY
    );

    always @(*) begin
        remainder_calc_start = (division_step_pulse == 1'b1) || ((remainder_calc_end == 1'b1) && (last_calculation == 1'b0));
    end

// Control the calculation step counter

    always @(*) begin
        calculation_step_clear = (load_inputs        == 1'b1);
        calculation_step_do    = (remainder_calc_end == 1'b1);
    end

// Control the divisor and remainder increment.

    always @(*) begin
        divide_by_zero_load         = (load_inputs    == 1'b1);
        divisor_load                = (load_inputs    == 1'b1);
        divisor_enable              = (load_inputs    == 1'b1) || (remainder_calc_end == 1'b1);
        divisor_sign_load           = (load_inputs    == 1'b1);
        remainder_increment_load    = (divisor_load   == 1'b1);
        remainder_increment_enable  = (divisor_enable == 1'b1);
    end

// Control the dividend and the remainder.

    always @(*) begin
        dividend_sign_load          = (load_inputs == 1'b1);
        remainder_load              = (load_inputs == 1'b1);
        remainder_enable            = (load_inputs == 1'b1) || (calculation_step_valid == 1'b1);
    end

// Control the quotient and quotient increment

    always @(*) begin
        quotient_increment_load   = (load_inputs == 1'b1);
        quotient_increment_enable = (load_inputs == 1'b1) || (remainder_calc_end == 1'b1);
        quotient_load             = (load_inputs == 1'b1);
        quotient_enable           = (load_inputs == 1'b1) || (calculation_step_valid == 1'b1);
    end

endmodule

