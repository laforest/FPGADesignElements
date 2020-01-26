`default_nettype none

/** Converts from Gray code (Reflected Binary Code) to an unsigned binary number
 * see en.wikipedia.org/wiki/Gray_code
 */

module Gray_to_Binary
#(
    parameter   WIDTH
)
(
    input  wire [WIDTH-1:0] gray_in,
    output wire [WIDTH-1:0] binary_out
);

    function automatic [WIDTH-1:0] gray_to_binary(input [WIDTH-1:0] gray);
        reg [WIDTH-1:0] binary;
        integer i;
    begin
        binary[WIDTH-1] = gray[WIDTH-1];
        for(i=WIDTH-2;i>=0;i=i-1)
            binary[i] = binary[i+1] ^ gray[i];
        gray_to_binary = binary;
    end
    endfunction

    assign binary_out = gray_to_binary(gray_in);

endmodule
