
//# A Priority Arbiter.

// Returns a one-hot bitmask of the least-significant bit set in a word, where
// bit 0 can be viewed as having highest priority. 
// There's no logic added here, but we wrap [the relevant bitmask
// module](./Bitmask_Isolate_Rightmost_1_Bit.html) to show the intended usage.

// A common use-case for an arbiter is to drive a [one-hot
// multiplexer](./Multiplexer_One_Hot.html) to select one of multiple senders
// requesting for one receiver, or one of multiple receivers requesting from
// one sender. This arrangement requires that the requestors can raise and
// hold a "request" signal, wait until they receive the "grant" signal to
// begin their transaction, and to drop "request" only once they are done.
// This is very similar to a ready/valid handshake, except that the
// transaction cannot be interrupted, else the granted access is lost.

// Note that if a higher-priority request happens too frequently, even if
// brief, it will starve lower priority requests. To reduce this effect, you
// need a [Round-Robin Arbiter](./Round_Robin_Arbiter.html), which is built-up
// from two Priority Arbiters.

`default_nettype none

module Priority_Arbiter
#(
    parameter WORD_WIDTH = 0
)
(
    input   wire    [WORD_WIDTH-1:0]    requests,
    output  reg     [WORD_WIDTH-1:0]    grant
);

    Bitmask_Isolate_Rightmost_1_Bit
    #(
        .WORD_WIDTH (WORD_WIDTH)
    )
    calc_grant 
    (
        .word_in    (requests),
        .word_out   (grant)
    );

endmodule

