#! /usr/bin/python3

# Simply output the usual structure of a new Verilog module definition file.
# Comments can be Markdown. Note the lack of leading space for headers.

skeleton = """//# Title

// Outline of function, etc... as text/Markdown/HTML

`default_nettype none

module NAME
#(
    parameter WORD_WIDTH = 0,
)
(
    input   wire                        clock,
    input   wire                        clear,

    input   wire    [WORD_WIDTH-1:0]    some_input,
    output  reg     [WORD_WIDTH-1:0]    some_output
);

    localparam WORD_ZERO = {WORD_WIDTH{1'b0}};

    initial begin
        some_output = WORD_ZERO;
    end

// Some comment explaining the next code

    always @(*) begin
        some_output = some_input;
    end

endmodule
"""
# The print() adds the trailing newline to make a blank line

if __name__ == "__main__":
    print(skeleton)

