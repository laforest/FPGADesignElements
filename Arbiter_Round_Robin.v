
//# A Round-Robin Arbiter

// Returns a one-hot grant bitmask selected from one of the raised request
// bits in a word, in round-robin order, going from least-significant bit
// (highest priority) to most-significant bit (lowest priority), and back
// around. *A grant is held until the request is released.*

// Unset request bits are skipped, which avoids wasting time. Requests can be
// raised or dropped before their turn comes, but this must be done
// synchronously to the clock. *Grants are calculated combinationally from the
// requests*, so pipeline as necessary. If the `requests_mask` bit
// corresponding to a `requests` bit is zero, then that request cannot be
// granted that cycle. The round-robin always continues from the last granted
// request, even after an idle period of no requests, unless `clear` is
// asserted.

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

// Here, we implement a "mask method" round-robin arbiter, as described in
// Section 4.2.4, Figure 12 of Matt Weber's [Arbiters: Design Ideas and Coding
// Styles](http://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.86.550&rep=rep1&type=pdf). 

// A round-robin arbiter is commonly used to fairly divide a resource amongst
// multiple requestors, *in proportion to each requestor's activity*, since
// each requestor holds a grant until they lower their request. Idle
// requestors don't use up any of the arbitrated resource. A frequent
// requestor will not obstruct other requestors perpetually.

// However, this round-robin arbiter does not deal with some subtleties of
// fairness. For example, it's possible that under normal operation, one
// requestor ends up placing a request always just before the previous
// requestor finishes. Thus, that new request waits less than the others. One
// solution periodically takes a snapshot of the current pending requests, and
// services all of these requests before refreshing the snapshot.

//### Customizations

// To enable the creation of custom fairness adjustments, the `requests_mask`
// input can be used to exclude one or more requests from being granted in the
// current cycle, and must be updated synchronously to the `clock`. The
// `requests_mask` is arbitrary, and if desired can be calculated from the
// current `requests`, the `grant_previous` one-hot output which always holds
// the last given grant even if the requests are currently all idle, and the
// current one-hot `grant` output.

// * Since a grant typically lasts longer than one cycle and won't get granted
// again for several cycles, taking multiple cycles to compute the next
// `requests_mask` is a valid option.
// * The `requests_mask` is applied combinationally to the `requests` input
// and to the internal `round_robin_mask`, both of which have a combinational
// path to `grant`, so pipeline as necessary. 

// If unused, leave `requests_mask` set to all-ones, and the masking logic
// will optimize away.

`default_nettype none

module Arbiter_Round_Robin
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

    localparam ZERO = {INPUT_COUNT{1'b0}};

    initial begin
        grant = ZERO;
    end

// We need to detect if any requests are active: *when all requests go idle,
// we want to remember the last granted request.* Otherwise, that lost state
// means the round-robin restarts from the highest priority request rather
// than the next lower priority request after the last granted request. 

// Always granting the highest priority first after an idle period allows
// a pathological request pattern to cause starvation: all but the highest
// priority request would starve if they keep asserting and de-asserting in
// lock-step after an idle period.

    reg any_requests_active = 1'b0;

    always @(*) begin
        any_requests_active = (requests != ZERO);
    end

// For the same reasons, we need to detect when we leave an idle request
// period so we can, for that cycle, refuse to grant again the last granted
// request, which would otherwise cause starvation of other requests happening
// in lock-step.

    wire out_from_idle;

    Pulse_Generator
    requests_restart
    (
        .clock              (clock),
        .level_in           (any_requests_active),
        .pulse_posedge_out  (out_from_idle),
        // verilator lint_off PINCONNECTEMPTY
        .pulse_negedge_out  (),
        .pulse_anyedge_out  ()
        // verilator lint_on  PINCONNECTEMPTY
    );

// Grant a request in priority order (LSB has higest priority) after applying
// `requests_mask`. This is the base case which starts the round-robin.

    reg [INPUT_COUNT-1:0] requests_masked_priority = ZERO;

    always @(*) begin
        requests_masked_priority = requests & requests_mask;
    end

    wire [INPUT_COUNT-1:0] grant_priority;

    Bitmask_Isolate_Rightmost_1_Bit
    #(
        .WORD_WIDTH (INPUT_COUNT)
    )
    priority_grants
    (
        .word_in    (requests_masked_priority),
        .word_out   (grant_priority)
    );

// Mask-off all requests *of equal and higher priority* than the request
// currently granted, from the previous cycle. This masking makes the
// round-robin progress towards lower priority requests as the previously
// granted higher priority requests are released. The `thermometer_mask` must
// be inverted before use.

    wire [INPUT_COUNT-1:0] thermometer_mask;

    Bitmask_Thermometer_to_Rightmost_1_Bit
    #(
        .WORD_WIDTH (INPUT_COUNT)
    )
    grant_mask
    (
        .word_in    (grant_previous),
        .word_out   (thermometer_mask)
    );

    reg [INPUT_COUNT-1:0] round_robin_mask = ZERO;

    always @(*) begin
        round_robin_mask = ~thermometer_mask;
    end

// The `round_robin_mask` excludes the currently granted request, which we
// don't want to interrupt, so we OR the currently granted request bit into
// the `round_robin_mask` so we only mask-off all *higher* priority requests,
// leaving the currently granted request as highest priority.

// **EXCEPTION:** If we are returning from an all-idle request phase, we
// instead zero-out that granted request bit, so the round-robin can resume to
// the next lower priority request based on the `round_robin_mask`, instead of
// possibly re-granting the same request again.

// The `round_robin_mask` is further masked, in the same manner, by the
// `requests_mask` input, which may prevent the granting of some `requests` of
// lower priority after the currently granted request is released.

    reg [INPUT_COUNT-1:0] requests_masked_round_robin   = ZERO;
    reg [INPUT_COUNT-1:0] grant_previous_gated          = ZERO;

    always @(*) begin
        grant_previous_gated        = (out_from_idle == 1'b1) ? ZERO : grant_previous;
        requests_masked_round_robin = requests & (round_robin_mask | grant_previous_gated) & (requests_mask | grant_previous_gated);
    end

// Grant a request in priority order, but from the round-robin masked
// requests, which only contain requests of equal or lower priority to the
// currently granted request, minus any requests further masked by the
// `requests_mask` input.

    wire [INPUT_COUNT-1:0] grant_round_robin;

    Bitmask_Isolate_Rightmost_1_Bit
    #(
        .WORD_WIDTH (INPUT_COUNT)
    )
    round_robin_grants
    (
        .word_in    (requests_masked_round_robin),
        .word_out   (grant_round_robin)
    );

// If no round-robin granted requests remain, then instead grant from the
// priority requests, which starts over the round-robin at the highest
// priority (LSB) request.  This also resets `round_robin_mask`.

    always @(*) begin
        grant = (grant_round_robin == ZERO) ? grant_priority : grant_round_robin; 
    end

// Remember the last granted request so we can compute `round_robin_mask` to
// exclude higher priority requests than the last granted request. If all
// requests go idle, don't update, so we can continue the round-robin from
// where we left off when requests appear again, to avoid starvation of lower
// priority requests.

    Register
    #(
        .WORD_WIDTH     (INPUT_COUNT),
        .RESET_VALUE    (ZERO)
    )
    previously_granted_request
    (
        .clock          (clock),
        .clock_enable   (any_requests_active),
        .clear          (clear),
        .data_in        (grant),
        .data_out       (grant_previous)
    );

endmodule

