
//# Binary To One-Hot Converter

// Generates an output bit vector of up to 2^N bits with one bit set
// representing the N-bit input binary value.

// The width of the output vector is limited by the Verilog implementation to
// about a million bits, which means a maximum input binary width of 20 bits.
// Also, for very large output vectors, the synthesis can take a very long
// time. But in practice, you will never get near these limits.

// The output vector width may be more or less than all possible binary values.
// If the binary value does not map to any of the output bits, the output vector
// stays at zero, meaning "no value".

// This module is of great use when translating an "address" into a number of
// enable signals to select or filter something, such as a portable
// [multiplexer](Multiplexer_Binary_Structural.html).

`default_nettype none

module Binary_to_One_Hot
#(
    parameter       BINARY_WIDTH        = 0,
    parameter       OUTPUT_WIDTH        = 0 
)
(
    input   wire    [BINARY_WIDTH-1:0]  binary_in,
    output  wire    [OUTPUT_WIDTH-1:0]  one_hot_out
);

// Instantiate an address decoder for each possible *output* value.
// This way, binary input values outside of the output range
// result in a zero output.

    generate
        genvar i;
        for (i=0; i < OUTPUT_WIDTH; i=i+1) begin : per_output
            Address_Decoder_Behavioural
            #(
                .ADDR_WIDTH (BINARY_WIDTH)
            )
            one_hot_bit
            (
                .base_addr  (i[BINARY_WIDTH-1:0]),
                .bound_addr (i[BINARY_WIDTH-1:0]),
                .addr       (binary_in),
                .hit        (one_hot_out[i])
            );
        end
    endgenerate

endmodule

