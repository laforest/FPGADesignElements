
//# Signed Integer Quotient

// Computes the signed quotient of the signed dividend and divisor, based on
// whether each [Remainder](./Remainder_Integer_Signed.html)
// addition/subtraction step is successful. Part of the [Signed Integer
// Divider](./Divider_Integer_Signed.html) module. **Not usable by itself.**

//## Ports and Constants

`default_nettype none

module Quotient_Integer_Signed
#(
    parameter WORD_WIDTH        = 0,
    parameter STEP_WORD_WIDTH   = 0
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

// We have to internally compute with one extra bit of range to match the
// behaviour of the Remainder calculations.

    localparam STEP_WORD_WIDTH_LONG = STEP_WORD_WIDTH + 1;

    localparam WORD_WIDTH_LONG  = WORD_WIDTH + 1;
    localparam WORD_ZERO_LONG   = {WORD_WIDTH_LONG{1'b0}};
    localparam WORD_ONE_LONG    = {{WORD_WIDTH_LONG-1{1'b0}},1'b1};
    localparam WORD_ONES_LONG   = {WORD_WIDTH_LONG{1'b1}};

//## Datapath

//### Divisor and Dividend Signs

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

// The quotient increment is added/subtracted to/from the quotient each time
// we could remove the divisor from the remainder.  Shift it right by 1 each
// calculation step, so we increment by decreasing multiples of 2 at each
// division step.

    reg                         quotient_increment_enable   = 1'b0;
    reg                         quotient_increment_load     = 1'b0;
    wire [WORD_WIDTH_LONG-1:0]  quotient_increment_reversed;

    Register_Pipeline
    #(
        .WORD_WIDTH     (1),
        .PIPE_DEPTH     (WORD_WIDTH_LONG),
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

//### Quotient Storage

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
        .original_input     (quotient_loaded),
        .adjusted_output    (quotient)
    );

//### Quotient Calculation

// Add or subtract depending on the signs of the inputs. We don't need to
// handle backpressure at the input handshake of the
// `Adder_Subtractor_Binary_Multiprecision` since we don't try to start a new
// operation until the previous one has completed and its results stored.

    reg quotient_add_sub = 1'b0;

    always @(*) begin
        quotient_add_sub = (divisor_sign_loaded == dividend_sign_loaded) ? ADD : SUB;
    end

    reg  quotient_input_valid  = 1'b0;
    wire quotient_output_valid;
    // Veril*tor cannot quite anaylze this signals path across the hierarchy.
    // This is not a synthesis bug.
    // verilator lint_off UNOPTFLAT
    reg  quotient_output_ready = 1'b0;
    // verilator lint_on  UNOPTFLAT

    Adder_Subtractor_Binary_Multiprecision
    #(
        .WORD_WIDTH         (WORD_WIDTH_LONG),
        .STEP_WORD_WIDTH    (STEP_WORD_WIDTH_LONG)
    )
    quotient_calc
    (
        .clock          (clock),
        .clock_enable   (1'b1),
        .clear          (clear),

        .input_valid    (quotient_input_valid),
        //verilator lint_off PINCONNECTEMPTY
        .input_ready    (),
        //verilator lint_on  PINCONNECTEMPTY

        .add_sub        (quotient_add_sub), // 0/1 -> A+B/A-B
        .A              (quotient_loaded),
        .B              (quotient_increment),

        .output_valid   (quotient_output_valid),
        .output_ready   (quotient_output_ready),

        .sum            (quotient_next),
        // verilator lint_off PINCONNECTEMPTY
        .carry_out  (),
        .carries    (),
        .overflow   ()
        // verilator lint_on  PINCONNECTEMPTY
    );

//## Control Path

//### States and Storage

// We denote state as two bits, with the following transitions:
// LOAD -> CALC -> DONE -> LOAD -> ... 
// We don't handle the fourth, impossible case.
// The state encoding is arbitrary.

    localparam                      STATE_WIDTH     = 2;
    localparam [STATE_WIDTH-1:0]    STATE_LOAD      = 2'b00;
    localparam [STATE_WIDTH-1:0]    STATE_CALC      = 2'b10;
    localparam [STATE_WIDTH-1:0]    STATE_DONE      = 2'b11;
    localparam [STATE_WIDTH-1:0]    STATE_ERROR     = 2'b01; // Never reached

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

//### Calculation Steps

// Each division takes `WORD_WIDTH_LONG` steps, from `WORD_WIDTH_LONG-1` to
// `0`, plus one step to initially load the dividend and divisor. Thus, we
// need a counter of the correct width.

    localparam STEPS_WIDTH      = clog2(WORD_WIDTH_LONG);
    localparam STEPS_INITIAL    = WORD_WIDTH_LONG - 1;
    localparam STEPS_ZERO       = {STEPS_WIDTH{1'b0}};
    localparam STEPS_ONE        = {{STEPS_WIDTH-1{1'b0}},1'b1};

// Count down WORD_WIDTH_LONG-1 calculation steps. Stops at zero, and reloads
// when leaving STATE_LOAD.

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

//### Input/Output/Control Handshakes

// Accept inputs when empty (after results are read out) or frehsly
// reset/cleared). Declare outputs valid when calculation is done.
// Signal a new calculation step each time the addition/subtraction is
// complete.

    always @(*) begin
        output_valid   = (state == STATE_DONE);
        input_ready    = (state == STATE_LOAD);
        control_ready  = (state == STATE_CALC) && (quotient_output_valid == 1'b1);
    end

//### Control Events

    reg load_inputs       = 1'b0; // When we load the dividend and divisor signs.
    reg read_outputs      = 1'b0; // When we read out the quotient.
    reg read_control      = 1'b0; // When we read in the calculation step status.
    reg calculating       = 1'b0; // High while performing the division steps.
    reg step_done         = 1'b0; // High when an add/sub completes and is ack'ed by other computations.
    reg last_calculation  = 1'b0; // High during the last calculation step.

    always @(*) begin
        load_inputs       = (input_ready   == 1'b1) && (input_valid   == 1'b1);
        read_outputs      = (output_valid  == 1'b1) && (output_ready  == 1'b1);
        read_control      = (control_valid == 1'b1) && (control_ready == 1'b1);
        calculating       = (state == STATE_CALC);
        step_done         = (read_control == 1'b1);
        last_calculation  = (read_control == 1'b1) && (calculation_step == STEPS_ZERO);
    end

// Past this point, we should not refer directly to the FSM states or
// inputs/outputs, but to these events which are combinations of states and
// signals.

//### State Transitions

// There is no handling of erroneous states.

    always @(*) begin
        state_next = (load_inputs       == 1'b1) ? STATE_CALC : state;
        state_next = (last_calculation  == 1'b1) ? STATE_DONE : state_next;
        state_next = (read_outputs      == 1'b1) ? STATE_LOAD : state_next;
    end

//### Calculation Steps Control

    always @(*) begin
        calculation_step_clear = (load_inputs == 1'b1) || (clear == 1'b1);
        calculation_step_do    = (step_done   == 1'b1);
    end

//### Adder/Subtractor Control

// Let the Adder/Subtractor run independently, but read out its value only
// when the control handshake (from the Remainder module) completes. This then
// allows the Adder/Subtractor's input handshake to complete.

    always @(*) begin
        quotient_input_valid  = (calculating   == 1'b1);
        quotient_output_ready = (control_valid == 1'b1);
    end

//### Input Storage Control

    always @(*) begin
        divisor_sign_enable  = (load_inputs == 1'b1);
        dividend_sign_enable = (load_inputs == 1'b1);
    end

//### Quotient and Increment Storage Control

// Store only an updated Quotient if the division step from the Remainder
// module was OK (could successfully remove the divisor from the dividend).

    always @(*) begin
        quotient_increment_enable = (load_inputs == 1'b1) || (step_done == 1'b1);
        quotient_increment_load   = (load_inputs == 1'b1);
        quotient_enable           = (load_inputs == 1'b1) || ((step_done == 1'b1) && (step_ok == 1'b1));
        quotient_clear            = (load_inputs == 1'b1) || (clear == 1'b1);
    end

endmodule 

