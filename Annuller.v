
//# Annuller (Both Kinds)

// Takes in a word-wide signal, and passes it through, unless `annul` is high,
// then the signal is gated to zero.  We put something this simple into
// a module since it conveys design intent (e.g.: "turn this opcode into
// a no-op"), and avoids an RTL schematic cluttered with a bunch of gates.

// Annulling shows up in many designs: instead of using a multiplexer, we can
// selectively annul all but one input and OR-reduce to a result, which uses
// the final LUTs more efficiently. 
// While this is how a multiplexer works internally, breaking it open like
// this allows us to control the pipelining directly (which is relevant if you
// are going to have a lot of inputs), and allows us to select alternative
// conflict resolutions if two or more inputs remain after annulling:

// * reduce them to a single result using AND/OR/XOR,
// * feed them to an arbiter so you can process each remaining input in sequence,
// * have multiple final stages do different things in parallel with the remaining inputs.

// Essentially, Annulling allows us to easily think about calculating multiple
// things in parallel and keeping only the results we want. However, throwing
// away work increases performance at the expense of efficiency. Try to use
// the lost information if you can.

//## Implementation Options

// Some experimentation by others has shown that CAD tools will pattern-match
// on the description of the gating operation, resulting in different
// synth results depending on whether you describe the signal gating using
// a multiplexer or an AND gate. The synthesized logic may end up using the
// reset/clear pin of a flip-flop, or may create AND-gate logic after the
// flip-flop, which then gets folded into other LUT logic. Thus, both
// implementation are available via the `IMPLEMENTATION` parameter.

// The Annuller implementation does not generally matter. However, on FPGAs, the
// reset/clear signal is common to all flip-flops in a group (*known as a CLB
// (Common Logic Block) for Xilinx, or a LAB (Logic Array block) for Intel*).
// Thus, flip-flops driven by different reset/clear logic cannot be packed
// together, though since an Annuller applies the same reset/clear logic to
// all signals, they should pack normally.

// Register retiming may also be affected, again due to the reset/clear
// signals, but again, this is a minor problem if one at all. Assume things
// are fine, and check your synthesis results if a bottleneck appears.

`default_nettype none

module Annuller
#(
    parameter       WORD_WIDTH          = 0,
    parameter       IMPLEMENTATION      = ""
)
(
    input   wire                        annul,
    input   wire    [WORD_WIDTH-1:0]    data_in,
    output  reg     [WORD_WIDTH-1:0]    data_out
);

    localparam ZERO = {WORD_WIDTH{1'b0}};

    initial begin
        data_out = ZERO;
    end

    generate
        if (IMPLEMENTATION == "MUX") begin
            always @(*) begin
                data_out = (annul == 1'b0) ? data_in : ZERO;
            end
        end
        else
        if (IMPLEMENTATION == "AND") begin
            always @(*) begin
                data_out = data_in & {WORD_WIDTH{annul == 1'b0}};
            end
        end
    endgenerate

endmodule

