
//# A Priority Arbiter

// Returns a one-hot bitmask of the least-significant bit set in a word, where
// bit 0 can be viewed as having highest priority. 

// The requestors must raise and hold a `requests` bit and wait until the
// corresponding `grant` bit rises to begin their transaction. At any point,
// the highest priority request is granted.  The grant remains for as long as
// the request is held without interruption, *or until a higher priority
// request appears*. Requesters can hold or drop their requests as desired, as
// this is a combinational circuit.

// This Priority Arbiter is the building block of more complex arbiters: By
// masking other requests with a mask derived from the grants, we can alter
// the priority scheme as desired, and guarantee the current grant cannot be
// interrupted by another request. 

// A common use-case for an arbiter is to drive a [one-hot
// multiplexer](./Multiplexer_One_Hot.html) to select one of multiple senders
// requesting for one receiver, or one of multiple receivers requesting from
// one sender.

// Note that if a higher-priority request happens too frequently, even if
// brief, it will starve lower priority requests. To distribute the grants
// fairly, you need a [Round-Robin Arbiter](./Arbiter_Round_Robin.html).

`default_nettype none

module Arbiter_Priority
#(
    parameter INPUT_COUNT = 0
)
(
    input   wire    [INPUT_COUNT-1:0]    requests,
    output  wire    [INPUT_COUNT-1:0]    grant
);

    Bitmask_Isolate_Rightmost_1_Bit
    #(
        .WORD_WIDTH (INPUT_COUNT)
    )
    calc_grant 
    (
        .word_in    (requests),
        .word_out   (grant)
    );

endmodule

