
//# Clock Switchover

// To be used to control a PLL or MMCM with two clock inputs, where the primary
// clock runs always, and a secondary clock eventually begins operating and
// replaces the primary clock, for example when we need to initially configure
// an external device which then provides us a source-synchronous clock for
// its data.

// The switchover only works once. When the secondary clock starts, it is
// expected to keep going. There is no failover back to the primary clock.

// Once the secondary clock has run for a total of
// `SECONDARY_CLOCK_WAIT_CYCLES`, then `secondary_clock_select` goes high and
// stays high. You usually feed that to the PLL or MMCM with a clock select
// input, or to a BUFGMUX. 

// The `secondary_clock_reset` also goes high for
// `SECONDARY_CLOCK_RESET_CYCLES` cycles so any downstream logic (particularly
// the PLL or MMCM) can begin operating properly on the secondary clock.

// All logic here is run on the secondary clock and its outputs are
// asynchronous to the primary clock. Thus any driven logic must be in reset
// during the clock switchover.

// If the secondary clock is of a different frequency or duty-cycle than the
// primary clock, you will need to tell your CAD tool that the final clock's
// frequency is variable, which affects place and route, and timing analysis.

`default_nettype none

module Clock_Switchover
#(
    parameter SECONDARY_CLOCK_WAIT_CYCLES   = 100,     // Active cycles before switchover to secondary clock
    parameter SECONDARY_CLOCK_RESET_CYCLES  = 10       // Cycles to hold the reset line high at switchover
)
(
    input   wire    secondary_clock,
    output  reg     secondary_clock_select,
    output  reg     secondary_clock_reset
);

    initial begin
        secondary_clock_select  = 1'b0;
        secondary_clock_reset   = 1'b0;
    end

    `include "clog2_function.vh"

//## Clock Select Counter

// This counter is enabled by default, and will start counting down when the
// secondary clock runs. Once it reaches zero, it halts permanently.

    localparam SELECT_COUNTER_WIDTH = clog2(SECONDARY_CLOCK_WAIT_CYCLES);
    localparam SELECT_COUNTER_ONE   = {{SELECT_COUNTER_WIDTH-1{1'b0}},1'b1};
    localparam SELECT_COUNTER_ZERO  = {SELECT_COUNTER_WIDTH{1'b0}};

    wire [SELECT_COUNTER_WIDTH-1:0] select_count_remaining;
    reg                             select_count_done       = 1'b0;
    reg                             select_count_run        = 1'b1;

    always @(*) begin
        select_count_done = (select_count_remaining == SELECT_COUNTER_ZERO);
        select_count_run  = (select_count_done      == 1'b0);
    end

    Counter_Binary
    #(
        .WORD_WIDTH     (SELECT_COUNTER_WIDTH),
        .INCREMENT      (SELECT_COUNTER_ONE),
        .INITIAL_COUNT  (SECONDARY_CLOCK_WAIT_CYCLES [SELECT_COUNTER_WIDTH-1:0])
    )
    select_counter
    (
        .clock          (secondary_clock),
        .clear          (1'b0),

        .up_down        (1'b1), // 0/1 --> up/down
        .run            (select_count_run),

        .load           (1'b0),
        .load_count     (SELECT_COUNTER_ZERO),

        .carry_in       (1'b0),
        // verilator lint_off PINCONNECTEMPTY
        .carry_out      (),
        .carries        (),
        .overflow       (),
        // verilator lint_on PINCONNECTEMPTY

        .count          (select_count_remaining)
    );

//## Clock Reset Counter 

// This counter is disabled by default. Once the secondary clock counter has
// run down to zero (`select_count_done` goes high), the reset counter counts
// down to zero, then halts permanently.

    localparam RESET_COUNTER_WIDTH = clog2(SECONDARY_CLOCK_RESET_CYCLES);
    localparam RESET_COUNTER_ONE   = {{RESET_COUNTER_WIDTH-1{1'b0}},1'b1};
    localparam RESET_COUNTER_ZERO  = {RESET_COUNTER_WIDTH{1'b0}};

    wire [RESET_COUNTER_WIDTH-1:0] reset_count_remaining;
    reg                            reset_count_done       = 1'b0;
    reg                            reset_count_run        = 1'b0;

    always @(*) begin
        reset_count_done = (reset_count_remaining == RESET_COUNTER_ZERO);
        reset_count_run  = (reset_count_done == 1'b0) && (select_count_done == 1'b1);
    end

    Counter_Binary
    #(
        .WORD_WIDTH     (RESET_COUNTER_WIDTH),
        .INCREMENT      (RESET_COUNTER_ONE),
        .INITIAL_COUNT  (SECONDARY_CLOCK_RESET_CYCLES [RESET_COUNTER_WIDTH-1:0])
    )
    reset_counter
    (
        .clock          (secondary_clock),
        .clear          (1'b0),

        .up_down        (1'b1), // 0/1 --> up/down
        .run            (reset_count_run),

        .load           (1'b0),
        .load_count     (RESET_COUNTER_ZERO),

        .carry_in       (1'b0),
        // verilator lint_off PINCONNECTEMPTY
        .carry_out      (),
        .carries        (),
        .overflow       (),
        // verilator lint_on PINCONNECTEMPTY

        .count          (reset_count_remaining)
    );

// Finally, when the secondary clock has run long enough, raise
// `secondary_clock_select`, and then until the reset count is done, raise
// `secondary_clock_reset`.

// We have to delay the clock select signal so it arrives at the PLL or other
// logic *after* reset is asserted. (This is required by AMD/Xilinx PLLs, at least.)

    wire select_count_done_delayed;

    Register_Pipeline_Simple
    #(
        .WORD_WIDTH     (1'b1),
        .PIPE_DEPTH     (3)
    )
    selector_delay
    (
        .clock          (secondary_clock),
        .clock_enable   (1'b1),
        .clear          (1'b0),
        .pipe_in        (select_count_done),
        .pipe_out       (select_count_done_delayed)
    );

    always @(*) begin
        secondary_clock_select  =  select_count_done_delayed;
        secondary_clock_reset   = (select_count_done == 1'b1) && (reset_count_done == 1'b0);
    end

endmodule

