
//# Dyadic Boolean Operator

// Computes one of the 16 possible two-variable (dyadic) Boolean operations,
// selectable at run-time, on the `A` and `B` input words.

// We implement the operator by using a multiplexer differently: each
// corresponding bit from the `A` and `B` inputs, taken together as a 2-bit
// number, selects one of the bits of a 4-bit truth table input to the
// multiplexer which describes the Boolean function.

// For example, if we take the corresponding bits of `A` and `B` as the 2-bit
// number `{A,B}` (i.e.: where the bit from A is the most-significant bit),
// then the binary truth table `1000` describes the `AND` Boolean operation,
// as only bit 3 of the truth table is set. For readability, you can include
// a [list of the possible truth tables](./Dyadic_Boolean_Operations.html)
// before using this module.

// This module is useful in ALU designs for data processing and in control
// logic to set expected conditions that must be met (e.g.: CPU branch logic,
// industrial process control).

`include "Dyadic_Boolean_Operations.vh"

`default_nettype none

module Dyadic_Boolean_Operator
#(
    parameter WORD_WIDTH = 0
)
(
    input   wire    [`DYADIC_TRUTH_TABLE_WIDTH-1:0] truth_table,
    input   wire    [WORD_WIDTH-1:0]                word_A,
    input   wire    [WORD_WIDTH-1:0]                word_B,
    output  wire    [WORD_WIDTH-1:0]                result
);

    generate
        genvar i;
        for(i = 0; i < WORD_WIDTH; i = i+1) begin: per_bit
            Multiplexer_Binary_Behavioural
            #(
                .WORD_WIDTH     (1),
                .ADDR_WIDTH     (`DYADIC_SELECTOR_WIDTH),
                .INPUT_COUNT    (`DYADIC_TRUTH_TABLE_WIDTH)
            )
            Boolean_Operator
            (
                .selector       ({word_A[i],word_B[i]}),    
                .words_in       (truth_table),
                .word_out       (result[i])
            );
        end
    endgenerate

endmodule

