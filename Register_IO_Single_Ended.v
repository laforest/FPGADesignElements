
//# A Single-Ended Input/Output Register 

// An Input/Output Register with extra attributes to make the CAD tool
// place it in special I/O register locations around the edge of the FPGA,
// thus reducing skew.  Also has extra debug inputs and outputs for on-chip
// test logic to avoid disturbing the placement of the I/O register.

//## Input or Output Usage

// * For an input I/O: set `DIRECTION` to `"INPUT"`, and connect the I/O input
// pin to `data_in`, and `data_out` to the receiving logic.
// * For an output I/O: set `DIRECTION` to `"OUTPUT"`, and connect the sending
// logic to `data_in` and the I/O output pin to `data_out`.

//## Debugging Support

// It's likely for the I/O Register to be inside another module and thus
// invisible. Connecting any logic at the same time as the I/O pin to
// `data_in` or `data_out` will prevent placing the I/O Register into an I/O
// location since we can only connect one thing at a time to an I/O pin. So we
// provide separate debug signals which do not touch the I/O pin.

// The `debug_out` port mirrors `data_out` and is usually brought out to the
// ports of the module enclosing the I/O Register, so you don't have to alter
// the module logic to monitor operation. While a given `debug_in_enable` bit
// is set, then the corresponding `debug_in` replaces the same `data_in` bit,
// which allows for injecting test signals without using extra pins.

//## Ports and Parameters

`default_nettype none

module Register_IO_Single_Ended
#(
    parameter                   WORD_WIDTH  = 0,
    parameter [WORD_WIDTH-1:0]  RESET_VALUE = 0,
    parameter                   DIRECTION   = "" // "INPUT" or "OUTPUT"
)
(
    input   wire                        clock,
    input   wire                        clock_enable,
    input   wire                        clear,

    input   wire    [WORD_WIDTH-1:0]    data_in,
    output  wire    [WORD_WIDTH-1:0]    data_out,

    input   wire    [WORD_WIDTH-1:0]    debug_in,
    input   wire    [WORD_WIDTH-1:0]    debug_in_enable,
    output  wire    [WORD_WIDTH-1:0]    debug_out
);

//## Registers with attributes

// This module is a specialization of the simple [Synchronous
// Register](./Register.html) module, since we must apply the attributes
// directly to the HDL register and not the module as a whole. See the
// Synchronous Register module for further documentation and discussion.

// Depending on your CAD tool, optimization passes may or may not remove and
// reconstruct the register and thus lose the attributes specifying placement
// of the register into an I/O buffer location. Also, applying other attributes
// may interfere with I/O buffer placement.

// Under Vivado, using a `DONT_TOUCH` attribute or constraint on this module,
// or the `data_reg` register, will prevent the `IOB` attribute from taking
// effect, as it inhibits *any* optimization, including placement into an IOB
// location. However, we must use a `KEEP` attribute to prevent optimization
// transformations on this register before placement, as mentioned above.

    // Quartus
    (* useioff = 1 *)

    // Vivado
    (* KEEP = "TRUE" *)
    (* IOB  = "TRUE" *)

    reg [WORD_WIDTH-1:0] data_reg = RESET_VALUE;

//## Clocking and Reset

// Here, we use the  "last assignment wins" idiom (See
// [Resets](./verilog.html#resets)) to implement reset.  This is also one
// place where we cannot use ternary operators, else the last assignment for
// clear (e.g.: `data_out <= (clear == 1'b1) ? RESET_VALUE : data_out;`) would
// override any previous assignment with the current value of `data_out` if
// `clear` is not asserted!

    wire [WORD_WIDTH-1:0] data_in_internal;

    always @(posedge clock) begin
        if (clock_enable == 1'b1) begin
            data_reg <= data_in_internal;
        end

        if (clear == 1'b1) begin
            data_reg <= RESET_VALUE;
        end
    end

//## Debug Support

// We also mimic the I/O Register with a conventional register taking a debug
// input. If a `debug_in_enable` bit is set, then the matching `debug_in`
// input bit will show up at the same `data_out` bit and `debug_out` bit
// outputs instead of `data_in`, with the same 1-cycle latency.  This enables
// generating signals and testing without having to use extra FPGA pins or
// disturbing the I/O register placement.

    reg  [WORD_WIDTH-1:0] debug_in_internal = RESET_VALUE;
    wire [WORD_WIDTH-1:0] debug_in_captured;

    Register
    #(
        .WORD_WIDTH     (WORD_WIDTH),
        .RESET_VALUE    (RESET_VALUE)
    )
    debug_reg
    (
        .clock          (clock),
        .clock_enable   (clock_enable),
        .clear          (clear),
        .data_in        (debug_in_internal),
        .data_out       (debug_in_captured)
    );

//## INPUT and OUTPUT logic

// We wire up the debug register and logic as necessary for `INPUT` or
// `OUTPUT` operation. The debug logic must never touch the I/O pin.

    generate

        // verilator lint_off WIDTH
        if (DIRECTION == "INPUT") begin
        // verilator lint_on  WIDTH

            Multiplexer_Bitwise_2to1
            #(
                .WORD_WIDTH (WORD_WIDTH)
            )
            debug_bit_select
            (
                .bitmask    (debug_in_enable),
                .word_in_0  (data_reg),
                .word_in_1  (debug_in_captured),
                .word_out   (data_out)
            );

            always @(*) begin
                debug_in_internal   = debug_in;
            end

            assign data_in_internal = data_in;
            assign debug_out        = data_out;
        end

        // verilator lint_off WIDTH
        if (DIRECTION == "OUTPUT") begin
        // verilator lint_on  WIDTH

            Multiplexer_Bitwise_2to1
            #(
                .WORD_WIDTH (WORD_WIDTH)
            )
            debug_bit_select
            (
                .bitmask    (debug_in_enable),
                .word_in_0  (data_in),
                .word_in_1  (debug_in),
                .word_out   (data_in_internal)
            );

            always @(*) begin
                debug_in_internal = data_in_internal;
            end

            assign data_out  = data_reg;
            assign debug_out = debug_in_captured;
        end

    endgenerate

endmodule

