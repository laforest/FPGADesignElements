
//# A Round-Robin Arbiter

// Returns a one-hot grant bitmask selected from one of the raised request
// bits in a word, in round-robin order, going from least-significant to
// most-significant bit, and back around.

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

// Grant a request in priority order (LSB has higest priority)

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
// currently granted, from the previous cycle. The mask must be inverted
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

// The mask includes the currently granted request, which we don't want to
// interrupt, so we OR `grant_previous` to the inverted mask to exclude the
// currently granted request from the mask, thus masking off all higher
// priority requests, leaving the currently granted request as highest
// priority.

    reg [INPUT_COUNT-1:0] requests_masked;

    always @(*) begin
        requests_masked = requests & (~mask | grant_previous);
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
// requests, which starts over granting from the highest (LSB) priority. This
// also resets the mask. And the round-robin process begins again.

    always @(*) begin
        grant = (grant_masked == ZERO) ? grant_raw : grant_masked; 
    end

    wire [INPUT_COUNT-1:0] grant_previous;

    Register
    #(
        .WORD_WIDTH     (INPUT_COUNT),
        .RESET_VALUE    (ZERO)
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

