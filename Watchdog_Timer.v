//# Watchdog Timer

// Raises an alarm signal if not "pinged" before a given number of cycles have
// passed since the last ping or since start. This can be used as a simple
// event timer, or as part of a hardware failsafe.

//## Operation

// If more cycles than the last loaded `cycle_count` have passed (except for
// a value of zero) since the last cycle `start`, or `ping` was pulsed high,
// the watchdog stops and raises and holds high `alarm` (but not `error`)
// until `start` is raised high to re-use the last loaded `cycle_count`. 

// `clear` overrides all signals, lowers all outputs, and stops the watchdog.
// So it's possible for `clear` to hide a timeout. *`clear` may be held high
// for multiple cycles without error.*

// `ping`, `load`, `start`, and `stop` are separate signals to separate the
// *controlling* process(es) (hardware and/or software) which configures and
// controls the watchdog (load/start/stop), and the *supervised* process which
// must periodically "ping" the watchdog, and to prevent the need for
// a duplicate external storage of the `cycle_count`. Typically, `load` is
// used by software controling processes which update the `cycle_count`, and
// `start` and `stop` are used by hardware controlling processes which only
// need to manage a pre-configured watchdog.

// `running` is high whenever the watchdog is counting down and not zero.
// Use it to determine if you should also start the watchdog when loading it.

//## Ping

// While the watchdog is running, pulsing `ping` high for exactly *one* cycle
// restarts the watchdog's timeout countdown with the last loaded
// `cycle_count`.  Holding `ping` high for more than one cycle stops the
// watchdog and raises `error` and `alarm`, to detect stuck-at faults in the
// supervised process.

// Raising `load` at the same time as `ping` restarts the watchdog with the
// new `cycle_count` value instead of the previously stored value.

// `ping` has no effect while the watchdog is stopped, so as to prevent a case
// where the alarm is raised, but not noticed before `ping` is raised again,
// which would clear the alarm and lose the detection of a timeout. This case
// also allows us to suspend using the watchdog, or to start the supervised
// process before the controlling process starts the watchdog.

//## Load

// Pulsing `load` for exactly *one* cycle while providing the desired
// `cycle_count` value in the same cycle will reload the watchdog internal
// `cycle_count` storage, *but does NOT clear `alarm` and `error`, does NOT
// start a stopped watchdog, and does NOT stop a running watchdog nor alter
// its current timeout*. Holding `load` high for more than one cycle stops the
// watchdog and raises `error` and `alarm` to detect stuck-at faults in the
// controlling process.

//## Start

// Pulsing `start` for exactly *one* cycle will reload the last loaded
// `cycle_count`, restart the watchdog and clear `alarm` and `error`. Holding
// `start` high for more than one cycle, or raising `start` while the watchdog
// is already running, stops the watchdog and raises `error` and `alarm` to
// detect stuck-at faults in the controlling process.

// Raising `load` at the same time as `start` starts the watchdog with the new
// `cycle_count` value instead of the previously stored value.

// Starting the watchdog with a `cycle_count` of zero halts the watchdog,
// clears `alarm` and `error`, and `ping` will have no effect. This special
// case allows us to choose to run without a watchdog, or to start the
// supervised process first, then the watchdog, in cases where we cannot be
// sure if the latency when configuring the watchdog or starting the
// supervised process will exceed the watchdog timeout. 

//## Stop

// Pulsing `stop` for exactly *one* cycle while the watchdog is running will
// stop the watchdog (by loading it with zero) and preserve the last loaded
// `cycle_count`. Holding `stop` high for more than one cycle, or raising
// `stop` while the watchdog is *not* running, stops the watchdog and raises
// `error` and `alarm` to detect faults in the controlling process.

// If the watchdog is running, raising `stop` and `load` together is allowed:
// the watchdog stops and the internal `cycle_count` storage is updated. 

// Raising `stop` and `start` together is always an error: if the watchdog is
// stopped then `stop` causes an error, else if the watchdog is running then
// `start` causes an error.

`default_nettype none

module Watchdog_Timer
#(
    parameter WORD_WIDTH                = 0
)
(
    input   wire                        clock,
    input   wire                        clear,

    // From supervised process
    input   wire                        ping,

    // From controlling process(es)
    input   wire                        start,
    input   wire                        stop,
    input   wire                        load,
    input   wire    [WORD_WIDTH-1:0]    cycle_count,

    output  wire                        alarm,
    output  wire                        error,
    output  reg                         running
);

    initial begin
        running = 1'b0;
    end

    localparam WORD_ZERO = {WORD_WIDTH{1'b0}};
    localparam WORD_ONE  = {{WORD_WIDTH-1{1'b0}}, 1'b1};

//## Storage and Counting

// Store the last `load`ed `cycle_count` so `ping` and `start` can reload it
// into the counter.

    reg                     store_cycle_count = 1'b0;
    wire [WORD_WIDTH-1:0]   cycle_count_stored;

    Register
    #(
        .WORD_WIDTH     (WORD_WIDTH),
        .RESET_VALUE    (WORD_ZERO)
    )
    cycle_count_storage
    (
        .clock          (clock),
        .clock_enable   (store_cycle_count),
        .clear          (clear),
        .data_in        (cycle_count),
        .data_out       (cycle_count_stored)
    );

// Simply a countdown timer which runs freely.
// Note that `clear` implicitly loads zero (INITIAL_COUNT).
// And a counter value of zero signals a stopped counter.

    reg                     timer_clear         = 1'b0;
    reg                     timer_run           = 1'b0;
    reg                     timer_load          = 1'b0;
    reg  [WORD_WIDTH-1:0]   timer_load_value    = WORD_ZERO;
    wire [WORD_WIDTH-1:0]   cycles_remaining;

    Counter_Binary
    #(
        .WORD_WIDTH     (WORD_WIDTH),
        .INCREMENT      (WORD_ONE),
        .INITIAL_COUNT  (WORD_ZERO)
    )
    timer_cycles
    (
        .clock          (clock),
        .clear          (timer_clear),

        .up_down        (1'b1), // 0/1 --> up/down
        .run            (timer_run),

        .load           (timer_load),
        .load_count     (timer_load_value),

        .carry_in       (1'b0),
        // verilator lint_off PINCONNECTEMPTY
        .carry_out      (),
        .carries        (),
        .overflow       (),
        // verilator lint_on  PINCONNECTEMPTY

        .count          (cycles_remaining)
    );

// We detect a timeout by the counter reaching 1, not zero, and raising the
// alarm in the next cycle.  This means loading zero directly, to stop the
// counter, does not trigger an alarm, and that loading a `cycle_count` value
// of N means the alarm will raise exactly N cycles later.

    reg timer_expiring = 1'b0;
    reg timer_stopped  = 1'b0;

    always @(*) begin
        timer_expiring  = (cycles_remaining == WORD_ONE);
        timer_stopped   = (cycles_remaining == WORD_ZERO);
        running         = (timer_stopped    == 1'b0);
    end

// Alarm is a latch. `clear` overrides `pulse_in`.

    reg alarm_clear = 1'b0;
    reg alarm_set   = 1'b0;

    Pulse_Latch
    #(
        .RESET_VALUE    (1'b0)
    )
    alarm_hold
    (
        .clock          (clock),
        .clear          (alarm_clear),
        .pulse_in       (alarm_set),
        .level_out      (alarm)
    );

// Error is a latch. `clear` overrides `pulse_in`.

    reg error_clear = 1'b0;
    reg error_set   = 1'b0;

    Pulse_Latch
    #(
        .RESET_VALUE    (1'b0)
    )
    error_hold
    (
        .clock          (clock),
        .clear          (error_clear),
        .pulse_in       (error_set),
        .level_out      (error)
    );

//## Error Detection

// We can detect if a signal is pulsed for longer than one cycle by seeing if
// they are still asserted after we combinationally generate a pulse from
// their rising edge.

    wire ping_first_cycle;

    Pulse_Generator
    ping_check
    (
        .clock              (clock),
        .level_in           (ping),
        .pulse_posedge_out  (ping_first_cycle),
        // verilator lint_off PINCONNECTEMPTY
        .pulse_negedge_out  (),
        .pulse_anyedge_out  ()
        // verilator lint_on  PINCONNECTEMPTY
    );

    wire start_first_cycle;

    Pulse_Generator
    start_check
    (
        .clock              (clock),
        .level_in           (start),
        .pulse_posedge_out  (start_first_cycle),
        // verilator lint_off PINCONNECTEMPTY
        .pulse_negedge_out  (),
        .pulse_anyedge_out  ()
        // verilator lint_on  PINCONNECTEMPTY
    );

    wire stop_first_cycle;

    Pulse_Generator
    stop_check
    (
        .clock              (clock),
        .level_in           (stop),
        .pulse_posedge_out  (stop_first_cycle),
        // verilator lint_off PINCONNECTEMPTY
        .pulse_negedge_out  (),
        .pulse_anyedge_out  ()
        // verilator lint_on  PINCONNECTEMPTY
    );

    wire load_first_cycle;

    Pulse_Generator
    load_check
    (
        .clock              (clock),
        .level_in           (load),
        .pulse_posedge_out  (load_first_cycle),
        // verilator lint_off PINCONNECTEMPTY
        .pulse_negedge_out  (),
        .pulse_anyedge_out  ()
        // verilator lint_on  PINCONNECTEMPTY
    );

    reg ping_error              = 1'b0;
    reg start_error             = 1'b0;
    reg stop_error              = 1'b0;
    reg load_error              = 1'b0;
    reg long_pulse_error        = 1'b0;

    always @(*) begin
        ping_error  = (ping  == 1'b1) && (ping_first_cycle  == 1'b0);
        start_error = (start == 1'b1) && (start_first_cycle == 1'b0);
        stop_error  = (stop  == 1'b1) && (stop_first_cycle  == 1'b0);
        load_error  = (load  == 1'b1) && (load_first_cycle  == 1'b0);
        long_pulse_error = ping_error | start_error | stop_error | load_error;
    end

// We don't distinguish sources of error in the end, so merge them together
// here to simplify later logic.

    reg any_error = 1'b0;

    always @(*) begin
        any_error = (long_pulse_error   == 1'b1);
        any_error = ((stop_first_cycle  == 1'b1) && (timer_stopped == 1'b1)) || (any_error == 1'b1);
        any_error = ((start_first_cycle == 1'b1) && (timer_stopped == 1'b0)) || (any_error == 1'b1);
    end

//## Control Logic

    always @(*) begin
        store_cycle_count   = (load_first_cycle == 1'b1);

        // Clear overrides set on a latch, so make sure we don't clear while
        // setting unless it's the actual `clear` signal, which overrides all.

        alarm_set           =  (any_error   == 1'b1) || (timer_expiring     == 1'b1);
        alarm_clear         = ((any_error   == 1'b0) && (start_first_cycle == 1'b1)) || (clear == 1'b1);

        error_set           = (any_error   == 1'b1);
        error_clear         = (alarm_clear == 1'b1);

        timer_clear         = (any_error == 1'b1) || (stop_first_cycle == 1'b1) || (clear == 1'b1);
        timer_run           = (cycles_remaining  != WORD_ZERO);
        timer_load          = (start_first_cycle == 1'b1) || ((ping_first_cycle == 1'b1) && (timer_stopped == 1'b0));
        timer_load_value    = (load_first_cycle  == 1'b1) ? cycle_count : cycle_count_stored;
    end

endmodule

