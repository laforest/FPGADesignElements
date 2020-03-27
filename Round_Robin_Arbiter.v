
//# A Round-Robin Arbiter

// Returns a one-hot grant bitmask selected from one of the raised request
// bits in a word, in round-robin order, going from least-significant to
// most-significant bit, and back around.  Unset request bits are skipped,
// which avoids wasting time. Requests can be raised or dropped before their
// turn comes, but this must be done synchronously to the clock. Grants take
// one cycle to update after the requests change.

// Here, we implement a "mask method" round-robin arbiter, as described in
// Section 4.2.4, Figure 12 of Matt Weber's [Arbiters: Design Ideas and Coding
// Styles](http://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.86.550&rep=rep1&type=pdf). 

// A round-robin arbiter is commonly used to fairly divide a resource amongst
// multiple requestors, in proportion to each requestor's activity. Idle
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

module Round_Robin_Arbiter
#(
    parameter WORD_WIDTH = 0
)
(
    input   wire                        clock,
    input   wire                        clear,
    input   wire    [WORD_WIDTH-1:0]    requests,
    output  wire    [WORD_WIDTH-1:0]    grant
);

    localparam ZERO = {WORD_WIDTH{1'b0}};

// Grant a request in priority order (LSB has higest priority)

    wire [WORD_WIDTH-1:0] grant_raw;

    Priority_Arbiter
    #(
        .WORD_WIDTH (WORD_WIDTH)
    )
    raw_grants
    (
        .requests   (requests),
        .grant      (grant_raw)
    );

// Mask-off all requests of higher priority than the request granted in the
// previous cycle.

    wire [WORD_WIDTH-1:0] mask;

    Bitmask_Thermometer_to_Rightmost_1_Bit
    #(
        .WORD_WIDTH (WORD_WIDTH)
    )
    grant_mask
    (
        .word_in    (grant),
        .word_out   (mask)
    );

    reg [WORD_WIDTH-1:0] requests_masked;

    always @(*) begin
        requests_masked = requests & mask;
    end

// Grant a request in priority order, but from the masked requests (equal or
// lower priority to the request granted last cycle)

    wire [WORD_WIDTH-1:0] grant_masked;

    Priority_Arbiter
    #(
        .WORD_WIDTH (WORD_WIDTH)
    )
    masked_grants
    (
        .requests   (requests_masked),
        .grant      (grant_masked)
    );

// If no granted requests remain after masking, then grant from the unmasked
// requests, which starts over granting from the highest (LSB) priority. This
// also resets the mask. And the process begins again.

    reg [WORD_WIDTH-1:0] grant_next = ZERO;

    always @(*) begin
        grant_next = (grant_masked == ZERO) ? grant_raw : grant_masked; 
    end

    Register
    #(
        .WORD_WIDTH     (WORD_WIDTH),
        .RESET_VALUE    (ZERO)
    )
    granted_requests
    (
        .clock          (clock),
        .clock_enable   (1'b1),
        .clear          (clear),
        .data_in        (grant_next),
        .data_out       (grant)
    );

endmodule

