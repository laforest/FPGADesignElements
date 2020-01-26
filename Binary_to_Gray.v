`default_nettype none

/** Converts from an unsigned binary number to Gray code (Reflected Binary Code)
 * see en.wikipedia.org/wiki/Gray_code
 */

module Binary_to_Gray
#(
    parameter WIDTH
)
(
    input  wire [WIDTH-1:0]  binary_in,
    output wire [WIDTH-1:0]  gray_out
);

    function automatic [WIDTH-1:0] binary_to_gray(input [WIDTH-1:0] binary);
        integer i;
        reg [WIDTH-1:0] gray;
        begin
            for(i=0;i<WIDTH-1;i=i+1)
                gray[i] = binary[i] ^ binary[i+1];
            gray[WIDTH-1] = binary[WIDTH-1];

            binary_to_gray = gray;
        end
    endfunction

    assign gray_out = binary_to_gray(binary_in);

endmodule
