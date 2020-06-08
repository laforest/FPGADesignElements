
//# Pipeline to Pulse Interface

// Converts a receiving ready/valid pipeline handshake into an input pulse
// interface to a connected module, and then converts that module's output
// pulse interface into a sending ready/valid pipeline handshake. The input
// and output pipeline handshakes are coupled so input data is accepted no
// faster than output data is generated and read out, and overlapping input
// and output is supported.
// *The path from the input pulse interface to the output pulse interface must
// have at least one pipeline stage. No combinational paths are allowed else
// the input and output ready/valid handshake logic will form a loop.*

//## Dealing with Irreducible Latency

// Sometimes a module will have some irreducible and possibly variable
// latency, where it takes multiple clock cycles between an updated input and
// the resulting updated output, *and you cannot update the input again until
// the output has updated*.  In other words, it has an initiation interval
// greater than 1.

// Lets constrain the interface of such a module to accept a new input with
// a one-cycle valid pulse, and to signal the updated output, 1 or more cycles
// later, with a corresponding one-cycle valid output pulse, and allow that we
// can simultaneously update the input and the output. *The updated output
// must remain constant until the next one-cycle valid output pulse.*

// Given these design constraints, we can consistenly convert those input and
// output pulse interfaces into input and output elastic pipeline interfaces
// (ready/valid handshake) which prevent updating the input faster than the
// output, maintain maximal throughput by overlapping input and output updates
// if possible, and do not require any knowledge of the duration of the
// module's irreducible latency.

// Note that the module's updated output can only be read out *once* from the
// elastic pipeline interface, even though it is held steady until the next
// output update. This constraint is necessary to meet some Kahn Process
// Network criteria (for future use), and to allow the module to use its
// output registers as part of its computations rather than have extra buffers
// to enable overlapping computation and communication. Instead, we provide
// that buffering via a [Pipeline Skid Buffer](./Pipeline_Skid_Buffer.html).

`default_nettype none

module Pipeline_to_Pulse
#(
    parameter WORD_WIDTH = 0
)
(
    input   wire                        clock,
    input   wire                        clear,

    // Pipeline input and output
    input   wire                        valid_in,
    output  reg                         ready_in,
    input   wire    [WORD_WIDTH-1:0]    data_in,

    output  wire                        valid_out,
    input   wire                        ready_out,
    output  wire    [WORD_WIDTH-1:0]    data_out,

    // Pulse interface to connected module
    // in -> module -> out
    output  reg                         module_pulse_in,
    output  reg     [WORD_WIDTH-1:0]    module_data_in,
    input   wire                        module_pulse_out,
    input   wire    [WORD_WIDTH-1:0]    module_data_out
);

    localparam WORD_ZERO = {WORD_WIDTH{1'b0}};

    initial begin
        ready_in        = 1'b1; // matches logic below for simulation
        module_data_in  = WORD_ZERO;
        module_pulse_in = 1'b0;
    end

// Express the usual conditions to complete a ready/valid handshake. The
// "internal" signals connect to a [Skid Buffer](./Pipeline_Skid_Buffer.html)
// that deals with the final output handshake to the downstream pipeline.

    reg input_handshake_done  = 1'b0;
    reg output_handshake_done = 1'b0;

    wire ready_out_internal;
    reg  valid_out_internal = 1'b0;

    always @(*) begin
        input_handshake_done    = (valid_in           == 1'b1) && (ready_in           == 1'b1);
        output_handshake_done   = (valid_out_internal == 1'b1) && (ready_out_internal == 1'b1);
    end

//## Input Handshake to Input Pulse

// Input data goes straight into the connected module once the input handshake
// is complete. The `input_handshake_done` signal will be interrupted and
// become a single-cycle pulse by later logic.

    always @(*) begin
        module_data_in  = data_in;
        module_pulse_in = input_handshake_done;
    end

// We need to have `ready_in` be 1 initially and after a `clear`, else we
// can't complete the initial input handshake (as the connected module has no
// input readiness signal by design) and nothing would ever start.  This
// initial state contradicts the later clearing of `ready_in_latched` back to
// zero once the input handshake is done. So we instead keep that initial
// state in a separate pulse latch. It starts cleared and will get set exactly
// *once* when the initial input handshake completes, and stay will stay
// constant until reset.

    wire initial_ready_in;

    Pulse_Latch
    #(
        .RESET_VALUE    (1'b0)
    )
    generate_initial_ready_in
    (
        .clock          (clock),
        .clear          (clear),
        .pulse_in       (input_handshake_done),
        .level_out      (initial_ready_in)
    );

// Now latch the value of `ready_in` which is set by completing the output
// handshake, and cleared by completing the input handshake (or by the
// top-level `clear` as reset).

    reg clear_ready_in_latched = 1'b0;

    always @(*) begin
        clear_ready_in_latched = (clear == 1'b1) || (input_handshake_done == 1'b1);
    end

    wire ready_in_latched;

    Pulse_Latch
    #(
        .RESET_VALUE    (1'b0)
    )
    generate_ready_in_latched
    (
        .clock      (clock),
        .clear      (clear_ready_in_latched),
        .pulse_in   (output_handshake_done),
        .level_out  (ready_in_latched)
    );

// Use the initial `ready_in` state, pass the output handshake completion
// directly to `ready_in` to remove a cycle of latency, and latch the
// `ready_in` state if we don't finish an input handshake right away.

    always @(*) begin
        ready_in = (ready_in_latched == 1'b1) || (output_handshake_done == 1'b1) || (initial_ready_in == 1'b0);
    end

//## Output Pulse to Output Handshake

// Now handle the output ready/valid handshake, starting when the connected
// module updates its output data to set `valid_out`, and completing the
// output ready/valid handshake to clear it.

    wire valid_out_latched;

    Pulse_Latch
    #(
        .RESET_VALUE    (1'b0)
    )
    generate_valid_out_latched
    (
        .clock          (clock),
        .clear          (output_handshake_done),
        .pulse_in       (module_pulse_out),
        .level_out      (valid_out_latched)
    );

// Pass the module output pulse directly, and also latch it, as
// `valid_out_internal`. This removes a cycle of latency and allows the output
// handshake to complete later.  We use "internal" signals, as the final Skid
// Buffer will provide the final output handshake to the enclosing module.

    always @(*) begin
        valid_out_internal = (valid_out_latched == 1'b1) || (module_pulse_out == 1'b1);
    end

// Buffer the output handshake to cut the backwards combinational path from
// `ready_out` to `ready_in`, to allow a transfer through the pulse-driven
// module every cycle if it supports it, and to buffer the output data so the
// next computation can begin immediately.

    Pipeline_Skid_Buffer
    #(
        .WORD_WIDTH (WORD_WIDTH)
    )
    buffer_out
    (
        .clock          (clock),
        .clear          (clear),

        .input_valid    (valid_out_internal),
        .input_ready    (ready_out_internal),
        .input_data     (module_data_out),

        .output_valid   (valid_out),
        .output_ready   (ready_out),
        .output_data    (data_out)
    );

endmodule

