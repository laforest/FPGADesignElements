
//# Synthesis Harness Output

// When developing a new module, it's very convenient to run it through your
// CAD tool by itself, on a smaller target FPGA, with any random automatic pin
// assignments, to iterate quickly and find synth and timing issues.
// However, you can run out of physical pins, and your logic will get
// scattered all over the FPGA as it tries to stay close to the pins, wrecking
// your timing estimates.  Also, any input or output logic which isn't
// registered won't be part of the STA (Static Timing Analysis), so that also
// makes the timing estimate less accurate when synthesized in isolation.

// A solution to both problems is to place your design in a harness of
// registers. For the outputs, we connect them all to a final bank of
// registers whose outputs are then XOR-reduced to a single bit, which
// virtually eliminates the problem of running out of pins, while still
// avoiding optimizing away any logic by accident since that final output is
// completely data-dependent. The output is meaningless for simulation, but
// that's not what we need it for right now.

// It would seem natural to do the reverse of the [Synthesis Harness
// Input](./Synthesis_Harness_Input.html) and do a parallel-to-serial
// conversion to the output bits to a single bit, but that might
// pollute our timing analysis since synth might create multiplexers
// between the outputs and the registers. So we bit-reduce instead.

// You must also constrain the harness registers to *not* be placed in the
// FPGA I/O registers so they will cluster around your logic, which will now
// tend to place all together in the center of the FPGA, giving you
// a reasonnably accurate timing estimate. 

// You can make the timing estimate more conservative by logically partioning
// the netlists of the design and the harness so they do not retime into
// eachother. You can make the timing estimate *even more* conservative by
// additionally physically partitioning (a.k.a. floorplanning) the netlists:
// place your design into a floorplan rectangle (or let the CAD tool do it
// automatically) and exclude the harness, which will then cluster around the
// design floorplan and approximate either connection from adjacent
// floorplans, or logic forced apart by congestion.

// A good way to use this module is to add up the widths of all your design
// outputs and use that sum as the `WORD_WIDTH` parameter, then connect
// a concatenation of all your output wires to the `word_in` port. The
// remaining harness ports can be connected to any suitable device pins.

`default_nettype none

module Synthesis_Harness_Output 
#(
    parameter   WORD_WIDTH = 0
)
(
    input       wire                        clock,
    input       wire                        areset,
    input       wire                        clear,
    input       wire    [WORD_WIDTH-1:0]    word_in,
    input       wire                        word_in_valid,
    output      reg                         bit_out
);

    localparam WORD_ZERO = {WORD_WIDTH{1'b0}};

    initial begin
        bit_out = 1'b0;
    end

    wire [WORD_WIDTH-1:0] word_out;

    // Vivado: don't put in I/O buffers, and keep netlists separate in
    // synth and implementation.
    (* IOB = "false" *)
    (* DONT_TOUCH = "true" *)

    // Quartus: don't use I/O buffers, and don't merge registers with others.
    (* useioff = 0 *)
    (* preserve *)

    Register_Pipeline
    #(
        .WORD_WIDTH     (WORD_WIDTH),
        .PIPE_DEPTH     (1),
        .RESET_VALUES   (WORD_ZERO)
    )
    word_register
    (
        .clock          (clock),
        .clock_enable   (word_in_valid),
        .areset         (areset),
        .clear          (clear),
        .parallel_load  (1'b0),
        .parallel_in    (WORD_ZERO),
        // verilator lint_off PINCONNECTEMPTY
        .parallel_out   (),
        // verilator lint_on  PINCONNECTEMPTY
        .pipe_in        (word_in),
        .pipe_out       (word_out)
    );

    always @(*) begin
        bit_out = ^word_out;
    end

endmodule

