
//# A Round-Robin Arbiter

// Returns a one-hot grant bitmask selected from one of the raised request
// bits in a word, in round-robin order, going from least-significant (highest
// priority) to most-significant (lowest priority) bit, and back around.

// Unset request bits are skipped, which avoids wasting time. Requests can be
// raised or dropped before their turn comes, but this must be done
// synchronously to the clock. Grants are calculated combinationally from the
// requests.

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

// A common use-case for an arbiter is to drive a [one-hot
// multiplexer](./Multiplexer_One_Hot.html) to select one of multiple senders
// requesting for one receiver, or one of multiple receivers requesting from
// one sender. This arrangement requires that the requestors can raise and
// hold a "request" signal, wait until they receive the "grant" signal to
// begin their transaction, and to drop "request" only once they are done.
// This is very similar to a ready/valid handshake, except that the
// transaction cannot be interrupted, else the granted access is lost.

`default_nettype none

module Arbiter_Round_Robin
#(
    parameter INPUT_COUNT = 0
)
(
    input   wire                        clock,
    input   wire                        clear,
    input   wire    [INPUT_COUNT-1:0]   requests,
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

// Grant a request in priority order (LSB has higest priority). This is the
// base case which starts the round-robin.

    wire [INPUT_COUNT-1:0] grant_raw;

    Arbiter_Priority
    #(
        .INPUT_COUNT (INPUT_COUNT)
    )
    raw_grants
    (
        .requests   (requests),
        .grant      (grant_raw)
    );

// Mask-off all requests of equal and higher priority than the request
// currently granted, from the previous cycle. This masking makes the
// round-robin progress towards lower priority requests as the previously
// granted higher priority requests are released. The mask must be inverted
// before use.

    wire [INPUT_COUNT-1:0] mask;

    Bitmask_Thermometer_to_Rightmost_1_Bit
    #(
        .WORD_WIDTH (INPUT_COUNT)
    )
    grant_mask
    (
        .word_in    (grant_previous),
        .word_out   (mask)
    );

// The mask includes the currently granted request, from the previous cycle,
// which we don't want to interrupt, so we OR the currently granted request
// bit into the inverted mask to exclude the currently granted request from
// the mask, thus masking off only all higher priority requests, leaving the
// currently granted request as highest priority, **EXCEPT** if we are
// returning from an idle request phase, when we instead zero-out that granted
// request bit, so the round-robin can resume to the next lower priority
// request based on the mask, instead of possibly re-granting the same request
// again.

    reg [INPUT_COUNT-1:0] requests_masked       = ZERO;
    reg [INPUT_COUNT-1:0] grant_previous_gated  = ZERO;

    always @(*) begin
        grant_previous_gated = (out_from_idle == 1'b1) ? ZERO : grant_previous;
        requests_masked      = requests & (~mask | grant_previous_gated);
    end

// Grant a request in priority order, but from the masked requests, which only
// contain requests of equal or lower priority to the currently granted request.

    wire [INPUT_COUNT-1:0] grant_masked;

    Arbiter_Priority
    #(
        .INPUT_COUNT (INPUT_COUNT)
    )
    masked_grants
    (
        .requests   (requests_masked),
        .grant      (grant_masked)
    );

// If no granted requests remain after masking, then grant from the unmasked
// requests, which starts over the round-robin granting from the highest (LSB)
// priority. This also resets the mask.

    always @(*) begin
        grant = (grant_masked == ZERO) ? grant_raw : grant_masked; 
    end

// Remember the last granted request so we can compute the mask to exclude
// higher priority requests than the last granted request. If all requests go
// idle, don't update, so we can continue the round-robin from where we left
// off when requests appear again.

    wire [INPUT_COUNT-1:0] grant_previous;

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

