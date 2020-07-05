
//# Pipeline to Pulse Interface

// Wraps a module with a pulse input interface inside a ready/valid input
// handshake interface. Supports full throughput (one input per cycle) if
// necessary, though that's not usually the case when this interface is
// needed.

// *The connected module must have at least one pipeline stage from input to
// output. No combinational paths allowed else the input and output handshake
// logic will form a loop.*

// When we have a module that cannot be fully pipelined due to a data
// dependency (e.g.: because of a backwards loop in the pipeline, or simply by
// the iterative nature of the implemented algorithm), and thus cannot accept
// a new input every cycle (i.e.: it has an initiation interval greater than
// 1), then we design the connected module to accept a new input with
// a one-cycle valid pulse

// This Pipeline to Pulse module converts a pipeline input with a ready/valid
// handshake into a pulse input interface and prevents updating the input
// faster than the connected module can handle, based on a separate signal
// which indicates that new data can be accepted, usually from a similar
// output handshake interface.

// We assume here that the connected module is not C-Slowed, though that is
// allowed. You will have to keep track of the separate computation streams
// yourself in the enclosing module.

`default_nettype none

module Pipeline_to_Pulse
#(
    parameter WORD_WIDTH = 0
)
(
    input   wire                        clock,
    input   wire                        clear,

    // Pipeline input
    input   wire                        valid_in,
    output  reg                         ready_in,
    input   wire    [WORD_WIDTH-1:0]    data_in,

    // Pulse interface to connected module input
    output  reg     [WORD_WIDTH-1:0]    module_data_in,
    output  reg                         module_data_in_valid,

    // Signal that the module can accept the next input
    input   wire                        module_ready
);

    localparam WORD_ZERO = {WORD_WIDTH{1'b0}};

    initial begin
        ready_in                = 1'b1; // matches logic below for simulation
        module_data_in          = WORD_ZERO;
        module_data_in_valid    = 1'b0;
    end

// Express the usual conditions to complete a ready/valid handshake. 

    reg input_handshake_done = 1'b0;

    always @(*) begin
        input_handshake_done = (valid_in == 1'b1) && (ready_in == 1'b1);
    end

// Input data goes straight into the connected module once the input handshake
// is complete. The `input_handshake_done` signal will be interrupted and
// become a single-cycle pulse by later logic.

    always @(*) begin
        module_data_in          = data_in;
        module_data_in_valid    = (input_handshake_done == 1'b1); 
    end

// We need to have `ready_in` be 1 both initially and after a `clear`, else we
// can't complete the initial input handshake (as the connected module has no
// input readiness signal, by design) and nothing would ever start.  This
// initial state contradicts the use of "clear" to bring `ready_in_latched`
// back to zero once the input handshake is done. So we instead keep that
// initial state in a separate pulse latch. It starts cleared and will get set
// exactly *once* when the initial input handshake completes, and stay
// constant until cleared.

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

// Now latch the value of `ready_in` which is set by signalling the connected
// module is ready, and cleared when completing the input handshake (or by
// `clear`).

    reg clear_ready_in_latched = 1'b0;

    always @(*) begin
        clear_ready_in_latched = (input_handshake_done == 1'b1) || (clear == 1'b1);
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
        .pulse_in   (module_ready),
        .level_out  (ready_in_latched)
    );

// Use the initial state, pass `module_ready` to `ready_in` to remove a cycle
// of latency, and latch the ready state if we don't finish an input handshake
// right away.

    always @(*) begin
        ready_in = (initial_ready_in == 1'b0) || (ready_in_latched == 1'b1) || (module_ready == 1'b1);
    end

endmodule

