
//# Signed Integer Divider by Powers of Two (Truncating Division), Multiprecision

// Correctly divides a *signed* integer by a power of two. Uses multiprecision
// arithmetic to allow working on larger integers at higher speed.

// This implementation is rather complex, with multiple parallel
// computation pipelines. Go read the original [Divider By Powers Of
// Two](./Divider_Integer_Signed_by_Powers_of_Two.html) implementation to more
// easily understand the (identical) algorithm. 

//## Theory of Operation

// While a left shift by N is always equivalent to a multiplication by
// 2<sup>N</sup> for both signed and unsigned binary integers, an arithmetic
// shift right by N is only a truncating division by 2<sup>N</sup> for
// *positive* binary integers. For negative integers, the result is a so-called
// modulus division, and the quotient ends up off by one in magnitude, and
// must be corrected by adding +1, *but only if an odd number results as part
// of the intermediate division steps*.

// The implementation is based on the PowerPC method, as described in <a
// href="./reading.html#Warren2013">Hacker's Delight</a>, Section 10-1, *"Signed
// Division by a Known Power of Two"*: We perform the right shift and take
// note if any 1-bits are shifted out. If so, add one to the shifted value.

// Since we divide only by powers of two, a division by zero cannot happen.
// (i.e.: there exists no N where 2<sup>N</sup> = 0) Also, we only allow
// positive exponents. A negative exponent would imply a multiplication, and
// that can be done directly with a left shift and not all this complication.

// Note that shifting by more than the WORD_WIDTH, with an exponent of value
// greater than WORD_WIDTH, will give a nonsense result for negative numbers
// as we only have WORD_WIDTH sign bits to shift in at most. 

//## Latency

// Since the result latency depends on the ratio of `WORD_WIDTH` to
// `STEP_WORD_WIDTH` and whether that ratio is a whole integer, the inputs are
// set with a ready/valid handshake, and can be updated after the output
// handshake completes. Adjust `PIPE_DEPTH` also as needed to meet timing
// across the Bit Shifters.

//## Parameters, Ports, and Constants

`default_nettype none

module Divider_Integer_Signed_by_Powers_of_Two_Multiprecision
#(
    parameter WORD_WIDTH        = 0,
    parameter STEP_WORD_WIDTH   = 0,
    parameter PIPE_DEPTH        = -1
)
(
    input   wire                        clock,
    input   wire                        clock_enable,
    input   wire                        clear,

    input   wire                        input_valid,
    output  wire                        input_ready,

    input  wire signed [WORD_WIDTH-1:0] numerator,
    input  wire        [WORD_WIDTH-1:0] exponent_of_two,

    output  wire                        output_valid,
    input   wire                        output_ready,

    output wire signed [WORD_WIDTH-1:0] quotient,
    output wire signed [WORD_WIDTH-1:0] remainder
);

// We depend on automatic width extension of the WORD_WIDTH integer here, as
// doing it using a loop in an initial block is worse for linting and CAD
// warnings.  I normally don't allow automatic width extension, but in this
// case it will always work, as the register will always store up to
// 2<sup>N</sup>-1 for a WORD_WIDTH of N, and N is always unsigned.  This
// width extension is necessary to match port widths later on. We do have to
// silence the linter, though.

    // verilator lint_off WIDTH
    reg [WORD_WIDTH-1:0] WORD_WIDTH_LONG = WORD_WIDTH;
    // verilator lint_on  WIDTH

    localparam NEGATIVE  = 1'b1;
    localparam WORD_ZERO = {WORD_WIDTH{1'b0}};

//## Inputs

// Fork the inputs to separate calculation pipelines.  We structure the
// calculations as initial calculations followed by corrections, for both
// quotient and remainder each.

    wire                    division_fork_valid;
    wire                    division_fork_ready;
    wire [WORD_WIDTH-1:0]   division_numerator;
    wire [WORD_WIDTH-1:0]   division_exponent;

    wire                    quotient_correction_fork_valid;
    wire                    quotient_correction_fork_ready;
    wire [WORD_WIDTH-1:0]   quotient_correction_numerator;
    wire [WORD_WIDTH-1:0]   quotient_correction_exponent;

    wire                    remainder_shift_amount_fork_valid;
    wire                    remainder_shift_amount_fork_ready;
    // verilator lint_off UNUSED
    wire [WORD_WIDTH-1:0]   remainder_shift_amount_numerator;
    // verilator lint_on  UNUSED
    wire [WORD_WIDTH-1:0]   remainder_shift_amount_exponent;

    wire                    remainder_correction_fork_valid;
    wire                    remainder_correction_fork_ready;
    wire [WORD_WIDTH-1:0]   remainder_correction_numerator;
    // verilator lint_off UNUSED
    wire [WORD_WIDTH-1:0]   remainder_correction_exponent;
    // verilator lint_on  UNUSED

    Pipeline_Fork_Eager
    #(
        .WORD_WIDTH     (WORD_WIDTH * 2),
        .OUTPUT_COUNT   (4)
    )
    input_fork
    (
        .clock          (clock),
        .clear          (clear),

        .input_valid    (input_valid),
        .input_ready    (input_ready),
        .input_data     ({numerator, exponent_of_two}),

        .output_valid   ({division_fork_valid,                   quotient_correction_fork_valid,                              remainder_shift_amount_fork_valid,                                 remainder_correction_fork_valid}),
        .output_ready   ({division_fork_ready,                   quotient_correction_fork_ready,                              remainder_shift_amount_fork_ready,                                 remainder_correction_fork_ready}),
        .output_data    ({division_numerator, division_exponent, quotient_correction_numerator, quotient_correction_exponent, remainder_shift_amount_numerator, remainder_shift_amount_exponent, remainder_correction_numerator, remainder_correction_exponent})
    );

//## Uncorrected Division

// Do the initial, uncorrected division.  The quotient may or may not be off
// by one at this point. It is corrected later.  The remainder is "short"
// because all its significant bits are at the left.  We will shift them, with
// sign extension, back to the right later.

// Prepare for a positive or negative numerator, which affects division
// calculations.

    reg                  division_numerator_sign = 1'b0;
    reg [WORD_WIDTH-1:0] division_sign_extension = WORD_ZERO;

    always @(*) begin
        division_numerator_sign = division_numerator [WORD_WIDTH-1];
        division_sign_extension = {WORD_WIDTH{division_numerator_sign}};
    end

    wire                    uncorrected_division_valid;
    wire                    uncorrected_division_ready;
    wire [WORD_WIDTH-1:0]   uncorrected_quotient;
    wire [WORD_WIDTH-1:0]   uncorrected_remainder;

    Bit_Shifter_Pipelined
    #(
        .WORD_WIDTH         (WORD_WIDTH),
        .PIPE_DEPTH         (PIPE_DEPTH)
    )
    uncorrected_division
    (
        .clock              (clock),
        .clear              (clear),

        .input_valid        (division_fork_valid),
        .input_ready        (division_fork_ready),

        .word_in_left       (division_sign_extension),
        .word_in            (division_numerator),
        .word_in_right      (WORD_ZERO),

        .shift_amount       (division_exponent),
        .shift_direction    (1'b1),             // 0/1 -> left/right

        .output_valid       (uncorrected_division_valid),
        .output_ready       (uncorrected_division_ready),

        // verilator lint_off PINCONNECTEMPTY
        .word_out_left      (),
        // verilator lint_on  PINCONNECTEMPTY
        .word_out           (uncorrected_quotient),
        .word_out_right     (uncorrected_remainder)
    );

// The outputs of the uncorrected division are then forked to both the
// quotient correction and remainder shifting calculations.

    wire                    uncorrected_quotient_fork_valid;
    wire                    uncorrected_quotient_fork_ready;
    wire [WORD_WIDTH-1:0]   uncorrected_quotient_quotient;
    wire [WORD_WIDTH-1:0]   uncorrected_remainder_quotient;

    wire                    uncorrected_remainder_fork_valid;
    wire                    uncorrected_remainder_fork_ready;
    // verilator lint_off UNUSED
    wire [WORD_WIDTH-1:0]   uncorrected_quotient_remainder;
    // verilator lint_on  UNUSED
    wire [WORD_WIDTH-1:0]   uncorrected_remainder_remainder;

    Pipeline_Fork_Eager
    #(
        .WORD_WIDTH     (WORD_WIDTH * 2),
        .OUTPUT_COUNT   (2)
    )
    uncorrected_division_fork
    (
        .clock          (clock),
        .clear          (clear),

        .input_valid    (uncorrected_division_valid),
        .input_ready    (uncorrected_division_ready),
        .input_data     ({uncorrected_quotient, uncorrected_remainder}),

        .output_valid   ({uncorrected_quotient_fork_valid,                               uncorrected_remainder_fork_valid}),
        .output_ready   ({uncorrected_quotient_fork_ready,                               uncorrected_remainder_fork_ready}),
        .output_data    ({uncorrected_quotient_quotient, uncorrected_remainder_quotient, uncorrected_quotient_remainder, uncorrected_remainder_remainder})
    );

// Then re-join the uncorrected division results with some of the original
// input data (numerator), forked for the quotient correction calculation.

    wire                    quotient_correction_valid;
    wire                    quotient_correction_ready;
    wire [WORD_WIDTH-1:0]   quotient_correction_quotient;
    wire [WORD_WIDTH-1:0]   quotient_correction_remainder;
    wire [WORD_WIDTH-1:0]   quotient_correction_numerator_joined;
    // verilator lint_off UNUSED
    wire [WORD_WIDTH-1:0]   quotient_correction_exponent_joined;
    // verilator lint_on  UNUSED

    Pipeline_Join
    #(
        .WORD_WIDTH     (WORD_WIDTH * 2),
        .INPUT_COUNT    (2)
    )
    quotient_correction_join
    (
        .clock          (clock),
        .clear          (clear),

        .input_valid    ({uncorrected_quotient_fork_valid,                               quotient_correction_fork_valid}),
        .input_ready    ({uncorrected_quotient_fork_ready,                               quotient_correction_fork_ready}),
        .input_data     ({uncorrected_quotient_quotient, uncorrected_remainder_quotient, quotient_correction_numerator, quotient_correction_exponent}),

        .output_valid   (quotient_correction_valid),
        .output_ready   (quotient_correction_ready),
        .output_data    ({quotient_correction_quotient, quotient_correction_remainder, quotient_correction_numerator_joined, quotient_correction_exponent_joined})
    );

//## Quotient Correction

// We need to know if at any point during the shift, a 1-bit was shifted into
// the remainder, indicating an odd-valued intermediate result, and thus an
// off-by-one error in the quotient. A simple OR-reduction works because we
// had primed that part of the shift with zeros.

    reg odd_intermediate_result = 1'b0;

    always @(*) begin
        odd_intermediate_result = (quotient_correction_remainder != WORD_ZERO);
    end

// Now, if the numerator was negative, and there was an odd-valued
// intermediate result, let's add +1 to the uncorrected_quotient to bring it
// back to the result a truncating division would give us.

    reg uncorrected_numerator_sign = 1'b0;
    reg correction                 = 1'b0;

    always @(*) begin
        uncorrected_numerator_sign = quotient_correction_numerator_joined [WORD_WIDTH-1];
        correction                 = (uncorrected_numerator_sign == NEGATIVE) && (odd_intermediate_result == 1'b1);
    end

    wire [WORD_WIDTH-1:0] correction_extended;

    Width_Adjuster
    #(
        .WORD_WIDTH_IN  (1),
        .SIGNED         (0),
        .WORD_WIDTH_OUT (WORD_WIDTH)
    )
    extended_correction
    (
        // It's possible some input bits are truncated away
        // verilator lint_off UNUSED
        .original_input     (correction),
        // verilator lint_on  UNUSED
        .adjusted_output    (correction_extended)
    );

    wire                    quotient_internal_valid;
    wire                    quotient_internal_ready;
    wire [WORD_WIDTH-1:0]   quotient_internal;

    Adder_Subtractor_Binary_Multiprecision
    #(
        .WORD_WIDTH         (WORD_WIDTH),
        .STEP_WORD_WIDTH    (STEP_WORD_WIDTH)
    )
    quotient_correction
    (
        .clock          (clock),
        .clock_enable   (clock_enable),
        .clear          (clear),

        .input_valid    (quotient_correction_valid),
        .input_ready    (quotient_correction_ready),

        .add_sub        (1'b0), // 0/1 -> A+B/A-B
        .A              (quotient_correction_quotient),
        .B              (correction_extended),

        .output_valid   (quotient_internal_valid),
        .output_ready   (quotient_internal_ready),

        .sum            (quotient_internal),
        // verilator lint_off PINCONNECTEMPTY
        .carry_out      (),
        .carries        (),
        .overflow       ()
        // verilator lint_on  PINCONNECTEMPTY
    );

//## Shift Remainder

// To shift the short remainder back to the right, we need to shift by the
// remainder of the distance to the right, which is WORD_WIDTH
// - exponent_of_two.

    wire                    remainder_shift_amount_valid;
    wire                    remainder_shift_amount_ready;
    wire [WORD_WIDTH-1:0]   remainder_shift_amount;

    Adder_Subtractor_Binary_Multiprecision
    #(
        .WORD_WIDTH         (WORD_WIDTH),
        .STEP_WORD_WIDTH    (STEP_WORD_WIDTH)
    )
    remainder_alignment
    (
        .clock          (clock),
        .clock_enable   (clock_enable),
        .clear          (clear),

        .input_valid    (remainder_shift_amount_fork_valid),
        .input_ready    (remainder_shift_amount_fork_ready),

        .add_sub        (1'b1), // 0/1 -> A+B/A-B
        .A              (WORD_WIDTH_LONG),
        .B              (remainder_shift_amount_exponent),

        .output_valid   (remainder_shift_amount_valid),
        .output_ready   (remainder_shift_amount_ready),

        .sum            (remainder_shift_amount),
        // verilator lint_off PINCONNECTEMPTY
        .carry_out      (),
        .carries        (),
        .overflow       ()
        // verilator lint_on  PINCONNECTEMPTY
    );

// Then join the short remainder from the uncorrected division with the
// remainder shift amount and the original numerator in preparation for the
// remainder correction calculation.

    wire                    remainder_join_valid;
    wire                    remainder_join_ready;
    wire [WORD_WIDTH-1:0]   remainder_shift_amount_joined;
    wire [WORD_WIDTH-1:0]   short_remainder_remainder_joined;
    wire [WORD_WIDTH-1:0]   remainder_correction_numerator_joined;

    Pipeline_Join
    #(
        .WORD_WIDTH     (WORD_WIDTH),
        .INPUT_COUNT    (3)
    )
    remainder_join
    (
        .clock          (clock),
        .clear          (clear),

        .input_valid    ({remainder_shift_amount_valid, uncorrected_remainder_fork_valid, remainder_correction_fork_valid}),
        .input_ready    ({remainder_shift_amount_ready, uncorrected_remainder_fork_ready, remainder_correction_fork_ready}),
        .input_data     ({remainder_shift_amount,       uncorrected_remainder_remainder,  remainder_correction_numerator}),

        .output_valid   (remainder_join_valid),
        .output_ready   (remainder_join_ready),
        .output_data    ({remainder_shift_amount_joined, short_remainder_remainder_joined, remainder_correction_numerator_joined})
    );

// Let's shift the remainder significant bits back to the right, with
// the same sign extension as the quotient if the remainder was not zero.

    reg                  remainder_correction_numerator_sign = 1'b0;
    reg [WORD_WIDTH-1:0] remainder_correction_sign_extension = WORD_ZERO;

    always @(*) begin
        remainder_correction_numerator_sign = remainder_correction_numerator_joined [WORD_WIDTH-1];
        remainder_correction_sign_extension = {WORD_WIDTH{remainder_correction_numerator_sign}};
    end

    wire                    remainder_internal_valid;
    wire                    remainder_internal_ready;
    wire [WORD_WIDTH-1:0]   remainder_internal;

    Bit_Shifter_Pipelined
    #(
        .WORD_WIDTH         (WORD_WIDTH),
        .PIPE_DEPTH         (PIPE_DEPTH)
    )
    remainder_correction
    (
        .clock              (clock),
        .clear              (clear),

        .input_valid        (remainder_join_valid),
        .input_ready        (remainder_join_ready),

        .word_in_left       (remainder_correction_sign_extension),
        .word_in            (short_remainder_remainder_joined),
        .word_in_right      (WORD_ZERO),

        .shift_amount       (remainder_shift_amount_joined),
        .shift_direction    (1'b1), // 0/1 -> left/right

        .output_valid       (remainder_internal_valid),
        .output_ready       (remainder_internal_ready),

        // verilator lint_off PINCONNECTEMPTY
        .word_out_left      (),
        .word_out           (remainder_internal),
        .word_out_right     ()
        // verilator lint_on  PINCONNECTEMPTY
    );

//## Outputs

// Finally, join the corrected remainder and quotient together into the final
// result.

    Pipeline_Join
    #(
        .WORD_WIDTH     (WORD_WIDTH),
        .INPUT_COUNT    (2)
    )
    output_join
    (
        .clock          (clock),
        .clear          (clear),

        .input_valid    ({remainder_internal_valid, quotient_internal_valid}),
        .input_ready    ({remainder_internal_ready, quotient_internal_ready}),
        .input_data     ({remainder_internal,       quotient_internal}),

        .output_valid   (output_valid),
        .output_ready   (output_ready),
        .output_data    ({remainder, quotient})
    );

endmodule

