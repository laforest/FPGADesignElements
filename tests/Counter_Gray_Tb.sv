`default_nettype none
`include "vunit_defines.svh"

// NOTE: VUnit requires lowercase testbench module name (probably a VHDL thing)
module counter_gray_tb();

    // VUnit parameters
    parameter output_path;
    parameter tb_path;

    parameter WIDTH;

    parameter PRINT=0;          // if true, prints binary -> gray -> binary conversion result to stdout

    localparam real CLK_PERIOD=10.0;

    // standard population count (# of 1's)
    function automatic integer popcount(input [WIDTH-1:0] v);
        integer n;
        integer i;
        n = 0;
        for (i=0;i<WIDTH;i=i+1)
            n += v[i];

        popcount = n;
    endfunction

    localparam EXPECTED_PERIOD=2**WIDTH;

    // clock generator

    reg clk;
    reg sresetn;

    always
        #(CLK_PERIOD/2) clk <= ~clk;


    // Stimulus generator

    reg binary_valid;
    reg [WIDTH-1:0] binary;
    reg [WIDTH-1:0] gray_last;


    // DUTs

    wire [WIDTH-1:0] gray_from_binary;
    wire [WIDTH-1:0] binary_from_gray;

    Binary_to_Gray#(WIDTH) dut_b2g (binary,          gray_from_binary);
    Gray_to_Binary#(WIDTH) dut_g2b(gray_from_binary,binary_from_gray);


    // round-trip conversion checker

    always@(posedge(clk))
        if (sresetn && binary_valid)
            `CHECK_EQUAL(binary, binary_from_gray);


    // keep track of last gray-code value

    always@(posedge(clk))
        if (!sresetn)
            gray_last <= 'x;
        else
            gray_last <= gray_from_binary;


    // print values

    always@(posedge clk)
        if (sresetn && PRINT)
        begin
            $write("Binary ");
            $writeb(binary);
            $write(" -> Gray ");
            $writeb(gray_from_binary);
            $write(" -> Binary ");
            $writeb(binary_from_gray);
            $display;
        end
    

    `TEST_SUITE begin

    `TEST_SUITE_SETUP begin
        clk <= 1'b0;
    end

    `TEST_CASE_SETUP begin
        sresetn <= 1'b0;
        binary_valid <= 1'b0;
        @(posedge(clk));
        sresetn <= 1'b1;
        @(posedge(clk));
    end


    // run a few more cycles than a full period, incrementing by one
    // at each step, ensure that one and only one bit has changed

    `TEST_CASE("full_period") begin
        binary          <= '0;
        binary_valid    <= 1'b0;
        @(posedge clk);
        for(integer i=0;i<2**WIDTH+4;i=i+1)
        begin
            binary          <= binary+1;
            binary_valid    <= 1'b1;
            @(posedge(clk));
            `CHECK_EQUAL(popcount(gray_from_binary ^ gray_last),1);
        end
    end

    `TEST_CASE_CLEANUP begin
    end

    `TEST_SUITE_CLEANUP begin
    end

    end

endmodule
