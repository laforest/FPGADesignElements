
//# List of Dyadic Boolean Truth Tables

// Include this file before using a [Dyadic Boolean
// Operator](./Dyadic_Boolean_Operator.html).

// Avoid redefinition warnings in case your CAD tool makes definitions exist
// across files.

`ifndef DYADIC_BOOLEAN_OPERATIONS
`define DYADIC_BOOLEAN_OPERATIONS

// Number of bits to define dyadic boolean operations. These never change.

    `define DYADIC_TRUTH_TABLE_WIDTH    4
    `define DYADIC_SELECTOR_WIDTH       2

// These truth tables assume A is the most-significant bit of the index into
// the truth table.

    `define DYADIC_ZERO         4'b0000
    `define DYADIC_A_AND_B      4'b1000
    `define DYADIC_A_AND_NOT_B  4'b0100
    `define DYADIC_A            4'b1100
    `define DYADIC_NOT_A_AND_B  4'b0010
    `define DYADIC_B            4'b1010
    `define DYADIC_A_XOR_B      4'b0110
    `define DYADIC_A_OR_B       4'b1110
    `define DYADIC_A_NOR_B      4'b0001
    `define DYADIC_A_XNOR_B     4'b1001
    `define DYADIC_NOT_B        4'b0101
    `define DYADIC_A_OR_NOT_B   4'b1101
    `define DYADIC_NOT_A        4'b0011
    `define DYADIC_NOT_A_OR_B   4'b1011
    `define DYADIC_A_NAND_B     4'b0111
    `define DYADIC_ONE          4'b1111

`endif

