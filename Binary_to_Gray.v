// Converts from an unsigned binary number to Gray code (Reflected Binary Code)
// see en.wikipedia.org/wiki/Gray_code
//
// See documentation in Gray_to_Binary.v

`default_nettype none

module Binary_to_Gray
#(
    parameter integer WIDTH=1
)
(
    input  wire [WIDTH-1:0]  binary_in,
    output reg  [WIDTH-1:0]  gray_out
);

    localparam ZERO = {WIDTH{1'b0}};

    function automatic [WIDTH-1:0] binary_to_gray(input [WIDTH-1:0] binary);
        integer i;
        reg [WIDTH-1:0] gray;
        begin
            for(i=0;i<WIDTH-1;i=i+1) begin
                gray[i] = binary[i] ^ binary[i+1];
            end
            gray[WIDTH-1] = binary[WIDTH-1];

            binary_to_gray = gray;
        end
    endfunction

    initial begin
        gray_out = ZERO;
    end

    
    always@(*) begin
        gray_out = binary_to_gray(binary_in);
    end

endmodule
