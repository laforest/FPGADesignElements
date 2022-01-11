
//# A Priority Arbiter

// Returns a one-hot grant bitmask of the least-significant bit set in a word,
// where bit 0 can be viewed as having highest priority. *A grant is held
// until the request is released.*

// The requestors must raise and hold a `requests` bit and wait until the
// corresponding `grant` bit rises to begin their transaction. *Grants are
// calculated combinationally from the requests*, so pipeline as necessary.
// The highest priority pending and unmasked request is granted once the
// currently granted request is released.  The grant remains for as long as
// the request is held without interruption. Requesters can raise or drop
// their requests before their turn comes, but this must be done synchronously
// to the clock.

//## Usage

// A common use-case for an arbiter is to drive a [one-hot
// multiplexer](./Multiplexer_One_Hot.html) to select one of multiple senders
// requesting for one receiver, or one of multiple receivers requesting from
// one sender. This arrangement requires that the requestors can raise and
// hold a `requests` bit, wait until they receive the correspondig `grant` bit
// to begin their transaction, and to drop their `requests` bit only once they
// are done.  This is very similar to a ready/valid handshake, except that the
// transaction cannot be interrupted, else the granted access is lost.

//## Fairness

// **A Priority Arbiter is not fair:** if a higher-priority request happens too
// frequently it will starve lower-priority requests, and if a lower-priority
// request holds its grant too long it will starve higher-priority requests,
// causing priority inversion. To distribute the grants fairly, you need
// a [Round-Robin Arbiter](./Arbiter_Round_Robin.html).

//### Customizations

// To enable the creation of custom fairness adjustments, the `requests_mask`
// input can be used to exclude one or more requests from being granted in the
// current cycle, and must be updated synchronously to the `clock`. The
// `requests_mask` is arbitrary, and if desired can be calculated from the
// current `requests`, the `grant_previous` one-hot output which holds the
// `grant` from the previous clock cycle, and the current one-hot `grant`
// output.

// * Since a grant typically lasts longer than one cycle and won't get granted
// again for several cycles, taking multiple cycles to compute the next
// `requests_mask` is a valid option.
// * The `requests_mask` is applied combinationally to the `requests` input
// and to the internal `grant_previous`, both of which have a combinational
// path to `grant`, so pipeline as necessary. 

// If unused, leave `requests_mask` set to all-ones, and the masking logic
// will optimize away.

`default_nettype none

module Arbiter_Priority
#(
    parameter INPUT_COUNT = 0
)
(
    input   wire                        clock,
    input   wire                        clear,

    input   wire    [INPUT_COUNT-1:0]   requests,
    input   wire    [INPUT_COUNT-1:0]   requests_mask,  // Set to all-ones if unused.
    output  wire    [INPUT_COUNT-1:0]   grant_previous,
    output  reg     [INPUT_COUNT-1:0]   grant
);

// First we filter the requests, masking off any externally disabled requestst
// (`requests_mask` bit is 0)

    localparam INPUT_ZERO = {INPUT_COUNT{1'b0}};

    reg  [INPUT_COUNT-1:0] requests_masked = INPUT_ZERO;

    always @(*) begin
        requests_masked = requests & requests_mask;
    end

// Then, from the remaining requests, we further mask out all but the highest
// priority (lowest bit) set request. This is the new grant candidate.

    wire [INPUT_COUNT-1:0] grant_candidate;
    Bitmask_Isolate_Rightmost_1_Bit
    #(
        .WORD_WIDTH (INPUT_COUNT)
    )
    priority_mask
    (
        .word_in    (requests_masked),
        .word_out   (grant_candidate)
    );

// If the request granted on the previous clock cycle is still active, hold it.
// Else, select the current candidate.   

    always @(*) begin
        grant = ((requests & grant_previous) != INPUT_ZERO) ? grant_previous : grant_candidate;
    end

// A grant cannot be interrupted by a higher priority request until the current 
// granted request is released. We need a register to store the current grant 
// for the next clock cycle.

    Register
    #(
        .WORD_WIDTH     (INPUT_COUNT),
        .RESET_VALUE    (INPUT_ZERO)
    )
    previously_granted_request
    (
        .clock          (clock),
        .clock_enable   (1'b1),
        .clear          (clear),
        .data_in        (grant),
        .data_out       (grant_previous)
    );

endmodule

