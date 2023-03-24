//# Pipeline Iterator

// A hardware for-loop. Drives an attached module over multiple iterations
// with an initial set of one or more data words stored in a FIFO. During each
// iteration, we refill the FIFO with either the initial data, or the output
// of the attached module.  During the last iteration, the output of the
// attached module is instead sent to the output interface, and the FIFO
// finishes empty.

// Since this Pipeline Iterator is itself a module with ready/valid handshakes
// at the input and output, it should be possible in theory to nest multiple
// Iterators to implement nested loops in hardware.

// In all cases, the module output MUST be of the same width and of the same
// number of words as the original input, without concern for the meaning or
// structure of the data words.

// The FIFO must be equal or deeper than the largest possible input data set,
// else the Iterator will PERMANENTLY hang during the initial data load since
// the FIFO will have filled up and cannot complete the initial load. *You
// will need to raise `clear` to make it work again.* To prevent this
// situation, be careful to never configure a data count greater than
// FIFO_DEPTH if DATA_COUNT_WIDTH makes it possible.

//## Operation

// First, set the number of data words, the number of iterations, and the
// feedback type (feedback input data (0), or feedback module output (1)) via the
// control interface. These settings are persistent, but cannot be changed
// after data begins to load, and until all iterations are complete.
// A setting of zero to one or both of the data count and iteration count will
// halt the Iterator until it is configured without any such zeros.

// Second, load the expected number of data words into the input interface,
// which will begin the iterations. The output interface will output the same
// number of data words during the last iteration. Note that the data count
// and word width are identical at the input and output: you may need a bit of
// width-adjusting wiring around the connected module to compensate if the
// output is not of the same width as the input (e.g.: an adder). If the
// number of output words is lesser (or greater), then you will need extra
// logic to pad (or trim) the output of the connected module back to the
// expected number of words. If you are feeding the module output back to the
// input, the module must be able to handle this padding.

//## Parameters and Ports

`default_nettype none

module Pipeline_Iterator
#(
    parameter WORD_WIDTH        = 0,        // Width of input and output
    parameter FIFO_RAMSTYLE     = "",       // FIFO RAM implementation
    parameter FIFO_DEPTH        = 0,        // FIFO depth MUST be deep enough to hold all data
    parameter ITER_COUNT_WIDTH  = 0,        // Width of iteration count value
    parameter DATA_COUNT_WIDTH  = 0         // Width of data count value 
)
(
    input   wire                            clock,
    input   wire                            clear,

    // Interface to configure the Iterator 
    input   wire                            control_valid,
    output  wire                            control_ready,
    input   wire    [ITER_COUNT_WIDTH-1:0]  iteration_count,
    input   wire    [DATA_COUNT_WIDTH-1:0]  data_count,
    input   wire                            feedback_type,

    // Interface for the input data
    input   wire                            input_valid,
    output  wire                            input_ready,
    input   wire    [WORD_WIDTH-1:0]        input_data,

    // Interface to the iterated module
    output  wire                            to_module_valid,
    input   wire                            to_module_ready,
    output  wire    [WORD_WIDTH-1:0]        to_module_data,

    // Interface from the iterated module
    input   wire                            from_module_valid,
    output  wire                            from_module_ready,
    input   wire    [WORD_WIDTH-1:0]        from_module_data,

    // Interface for the final output data
    output  wire                            output_valid,
    input   wire                            output_ready,
    output  wire    [WORD_WIDTH-1:0]        output_data
    
);

//## Input Selector

// Here we select the input to feed into the FIFO: the initial input data, the
// FIFO output, the attached module output, or none (when not configured or
// halted).

    localparam INPUT_SOURCE_COUNT   = 3; // new data, buffered data, or module output
    localparam INPUT_SELECT_NONE    = 3'b000;
    localparam INPUT_SELECT_INPUT   = 3'b100;
    localparam INPUT_SELECT_FIFO    = 3'b010;
    localparam INPUT_SELECT_MODULE  = 3'b001;

    reg  [INPUT_SOURCE_COUNT-1:0] input_select_one_hot = INPUT_SELECT_NONE;

    wire                    fifo_feedback_valid;
    wire                    fifo_feedback_ready;
    wire [WORD_WIDTH-1:0]   fifo_feedback_data;

    wire                    module_feedback_valid;
    wire                    module_feedback_ready;
    wire [WORD_WIDTH-1:0]   module_feedback_data;

    wire                    input_selector_valid;
    wire                    input_selector_ready;
    wire [WORD_WIDTH-1:0]   input_selector_data;

    wire input_valid_arbitrated;    // See control logic down below.

    Pipeline_Merge_One_Hot
    #(
        .WORD_WIDTH         (WORD_WIDTH),
        .INPUT_COUNT        (INPUT_SOURCE_COUNT),
        .HANDSHAKE_MERGE    ("OR"),
        .DATA_MERGE         ("OR"),
        .IMPLEMENTATION     ("AND")
    )
    input_selector
    (
        .clock          (clock),
        .clear          (clear),

        .selector       (input_select_one_hot),

        .input_valid    ({input_valid_arbitrated, fifo_feedback_valid, module_feedback_valid}),
        .input_ready    ({input_ready,            fifo_feedback_ready, module_feedback_ready}),
        .input_data     ({input_data,             fifo_feedback_data,  module_feedback_data }),

        .output_valid   (input_selector_valid),
        .output_ready   (input_selector_ready),
        .output_data    (input_selector_data)
    );

//## FIFO Buffer

// The selected input then goes into a FIFO buffer which we initially loaded
// with input data. Then, during each iteration, the FIFO simultaneously
// empties that data into the attached module and refills itself with either
// the FIFO's output or the attached module's output, except for the last
// iteration, when the FIFO empties itself only.

    wire                    fifo_valid;
    wire                    fifo_ready;
    wire [WORD_WIDTH-1:0]   fifo_data;

    Pipeline_FIFO_Buffer
    #(
        .WORD_WIDTH      (WORD_WIDTH),
        .DEPTH           (FIFO_DEPTH),
        .RAMSTYLE        (FIFO_RAMSTYLE),
        .CIRCULAR_BUFFER (0)
    )
    data_buffer
    (
        .clock          (clock),
        .clear          (clear),

        .input_valid    (input_selector_valid),
        .input_ready    (input_selector_ready),
        .input_data     (input_selector_data),

        .output_valid   (fifo_valid),
        .output_ready   (fifo_ready),
        .output_data    (fifo_data)
    );

// We must gate the output of the FIFO to stop sending data to the module once
// `data_count` items have been sent. We then (elsewhere) wait for the module
// to have output `data_count` items before we let the next iteration start.
// We must do this else, if the module has an internal pipeline deeper than
// the number of items to process, we can end up repeating the `data_count`
// too many times while we wait for the module to complete its output.

    reg gate_fifo_output = 1'b0;

    wire                    fifo_valid_gated;
    wire                    fifo_ready_gated;
    wire [WORD_WIDTH-1:0]   fifo_data_gated;


    Pipeline_Gate
    #(
        .WORD_WIDTH     (WORD_WIDTH),
        .IMPLEMENTATION ("AND"),
        .GATE_DATA      (0)
    )
    fifo_output_gate
    (
        .enable         (gate_fifo_output == 1'b0),

        .input_valid    (fifo_valid),
        .input_ready    (fifo_ready),
        .input_data     (fifo_data),

        .output_valid   (fifo_valid_gated),
        .output_ready   (fifo_ready_gated),
        .output_data    (fifo_data_gated)
    );

//## Forks and Sinks (Datapath Steering)

//### FIFO Output Fork

// We fork the FIFO output to feed both the attached module and the FIFO
// input when feeding back. This blocking fork also controls when we allow data to
// proceed to the attached module (see sink below), and prevents the feedback
// loop from running ahead of the attached module.

    wire                    fifo_sink_valid;
    wire                    fifo_sink_ready;
    wire [WORD_WIDTH-1:0]   fifo_sink_data;

    Pipeline_Fork_Blocking
    #(
        .WORD_WIDTH     (WORD_WIDTH),
        .OUTPUT_COUNT   (2)
    )
    fifo_fork
    (
        .clock          (clock),
        .clear          (clear),

        .input_valid    (fifo_valid_gated),
        .input_ready    (fifo_ready_gated),
        .input_data     (fifo_data_gated),

        .output_valid   ({fifo_sink_valid, to_module_valid}),
        .output_ready   ({fifo_sink_ready, to_module_ready}),
        .output_data    ({fifo_sink_data,  to_module_data})
    );

// If we are not feeding back the FIFO output to the FIFO input, and we need
// to let data through to the attached module, then sink the feedback branch
// of the blocking fork so it cannot block the branch feeding the attached
// module.

// Otherwise, during the initial load, do not sink the feedback branch: it
// will reach the input selector which is currently loading from input, which
// blocks the feedback path, and thus the blocking fork, and thus the output to
// the attached module, effectively gating the output of the FIFO.

    reg sink_fifo_feedback = 1'b0;

    Pipeline_Sink
    #(
        .WORD_WIDTH     (WORD_WIDTH),
        .IMPLEMENTATION ("AND")

    )
    fifo_feedback_sink
    (
        .sink           (sink_fifo_feedback),

        .input_valid    (fifo_sink_valid),
        .input_ready    (fifo_sink_ready),
        .input_data     (fifo_sink_data),

        .output_valid   (fifo_feedback_valid),
        .output_ready   (fifo_feedback_ready),
        .output_data    (fifo_feedback_data)
    );

//### Module Output Fork

// Fork the module output to feed both the Iterator output and the module
// feedback path. The fork must be blocking so the count of transfers through
// both forks remains the same at any time. (This means needing only one
// counter, and simpler logic.)

    wire                    module_fork_valid;
    wire                    module_fork_ready;
    wire [WORD_WIDTH-1:0]   module_fork_data;

    wire                    output_fork_valid;
    wire                    output_fork_ready;
    wire [WORD_WIDTH-1:0]   output_fork_data;

    Pipeline_Fork_Blocking
    #(
        .WORD_WIDTH     (WORD_WIDTH),
        .OUTPUT_COUNT   (2)
    )
    module_fork
    (
        .clock          (clock),
        .clear          (clear),

        .input_valid    (from_module_valid),
        .input_ready    (from_module_ready),
        .input_data     (from_module_data),

        .output_valid   ({module_fork_valid, output_fork_valid}),
        .output_ready   ({module_fork_ready, output_fork_ready}),
        .output_data    ({module_fork_data,  output_fork_data})
    );

// Sink the module output feedback path when not feeding the module output
// back to the FIFO.

    reg sink_module_feedback = 1'b0;

    Pipeline_Sink
    #(
        .WORD_WIDTH     (WORD_WIDTH),
        .IMPLEMENTATION ("AND")

    )
    module_feeback_sink
    (
        .sink           (sink_module_feedback),

        .input_valid    (module_fork_valid),
        .input_ready    (module_fork_ready),
        .input_data     (module_fork_data),

        .output_valid   (module_feedback_valid),
        .output_ready   (module_feedback_ready),
        .output_data    (module_feedback_data)
    );

// Sink the module output to the Iterator output when not in the final
// iteration, to both keep the Iterator output idle and prevent blocking the
// module feedback path (if used).

    reg sink_output = 1'b0;

    Pipeline_Sink
    #(
        .WORD_WIDTH     (WORD_WIDTH),
        .IMPLEMENTATION ("AND")
    )
    output_sink
    (
        .sink           (sink_output),

        .input_valid    (output_fork_valid),
        .input_ready    (output_fork_ready),
        .input_data     (output_fork_data),

        .output_valid   (output_valid),
        .output_ready   (output_ready),
        .output_data    (output_data)
    );

//## Control Logic

//### Feedback Type

// We take feedback either from the FIFO output, or the module output.

    localparam FEEDBACK_FIFO    = 1'b0;
    localparam FEEDBACK_MODULE  = 1'b1;

    reg  feedback_type_store = 1'b0;
    wire feedback_type_gated;
    wire feedback_type_stored;

    Register
    #(
        .WORD_WIDTH     (1),
        .RESET_VALUE    (FEEDBACK_FIFO)
    )
    feedback_type_storage
    (
        .clock          (clock),
        .clock_enable   (feedback_type_store),
        .clear          (clear),
        .data_in        (feedback_type_gated),
        .data_out       (feedback_type_stored)
    );

//### Iteration Count Storage

// How many times to send the data_count set of words to the attached module.
// The initial FIFO load does not count as an iteration, and the last
// iteration has no feedback, so the FIFO can finish empty.

    localparam ITER_COUNT_ZERO = {ITER_COUNT_WIDTH{1'b0}};
    localparam ITER_COUNT_ONE  = {{ITER_COUNT_WIDTH-1{1'b0}},1'b1}; 
    localparam ITER_COUNT_TWO  = {{ITER_COUNT_WIDTH-2{1'b0}},2'b10}; 

    reg                         iteration_count_store = 1'b0;
    wire [ITER_COUNT_WIDTH-1:0] iteration_count_gated;
    wire [ITER_COUNT_WIDTH-1:0] iteration_count_stored;

    Register
    #(
        .WORD_WIDTH     (ITER_COUNT_WIDTH),
        .RESET_VALUE    (ITER_COUNT_ZERO)
    )
    iteration_count_storage
    (
        .clock          (clock),
        .clock_enable   (iteration_count_store),
        .clear          (clear),
        .data_in        (iteration_count_gated),
        .data_out       (iteration_count_stored)
    );

//### Iteration Counter

// To simplify the logic, let's short-circuit and load the counter directly
// from the control input, as well as load iteration_count_storage for later
// use.

    reg                         iteration_count_run             = 1'b0;
    reg                         iteration_count_load            = 1'b0;
    reg                         iteration_count_load_initial    = 1'b0;
    reg  [ITER_COUNT_WIDTH-1:0] iteration_count_load_value      = ITER_COUNT_ZERO;
    wire [ITER_COUNT_WIDTH-1:0] iteration_count_remaining;

    always @(*) begin
        iteration_count_load_value = (iteration_count_load_initial == 1'b1) ? iteration_count : iteration_count_stored;
    end

    Counter_Binary
    #(
        .WORD_WIDTH     (ITER_COUNT_WIDTH),
        .INCREMENT      (ITER_COUNT_ONE),
        .INITIAL_COUNT  (ITER_COUNT_ZERO)
    )
    iteration_counter
    (
        .clock          (clock),
        .clear          (clear),

        .up_down        (1'b1), // 0/1 --> up/down
        .run            (iteration_count_run),

        .load           (iteration_count_load),
        .load_count     (iteration_count_load_value),

        .carry_in       (1'b0),
        // verilator lint_off PINCONNECTEMPTY
        .carry_out      (),
        .carries        (),
        .overflow       (),
        // verilator lint_on  PINCONNECTEMPTY

        .count          (iteration_count_remaining)
    );

//### Data Count Storage

// How many data words to load in the FIFO, to send to the attached
// module at each iteration, and to receive from the attached module at each
// iteration.

    localparam DATA_COUNT_ZERO  = {DATA_COUNT_WIDTH{1'b0}};
    localparam DATA_COUNT_ONE   = {{DATA_COUNT_WIDTH-1{1'b0}},1'b1}; 

    reg                         data_count_store = 1'b0;
    wire [DATA_COUNT_WIDTH-1:0] data_count_gated;
    wire [DATA_COUNT_WIDTH-1:0] data_count_stored;

    Register
    #(
        .WORD_WIDTH     (DATA_COUNT_WIDTH),
        .RESET_VALUE    (DATA_COUNT_ZERO)
    )
    data_count_storage
    (
        .clock          (clock),
        .clock_enable   (data_count_store),
        .clear          (clear),
        .data_in        (data_count_gated),
        .data_out       (data_count_stored)
    );

//### Data Counter

// To simplify the logic, let's short-circuit and load the counter directly
// from the control input, as well as load data_count_storage for later use.

    reg                         data_count_run          = 1'b0;
    reg                         data_count_load         = 1'b0;
    reg                         data_count_load_initial = 1'b0;
    reg  [DATA_COUNT_WIDTH-1:0] data_count_load_value   = DATA_COUNT_ZERO;
    wire [DATA_COUNT_WIDTH-1:0] data_count_remaining;

    always @(*) begin
        data_count_load_value = (data_count_load_initial == 1'b1) ? data_count : data_count_stored;
    end

    Counter_Binary
    #(
        .WORD_WIDTH     (DATA_COUNT_WIDTH),
        .INCREMENT      (DATA_COUNT_ONE),
        .INITIAL_COUNT  (DATA_COUNT_ZERO)
    )
    data_counter
    (
        .clock          (clock),
        .clear          (clear),

        .up_down        (1'b1), // 0/1 --> up/down
        .run            (data_count_run),

        .load           (data_count_load),
        .load_count     (data_count_load_value),

        .carry_in       (1'b0),
        // verilator lint_off PINCONNECTEMPTY
        .carry_out      (),
        .carries        (),
        .overflow       (),
        // verilator lint_on  PINCONNECTEMPTY

        .count          (data_count_remaining)
    );

//### Processed Data Counter

// Let's have another, identical counter, but for the attached module output,
// to count the number of items which have gone through the module and any
// later pipeline buffering (so we don't have stale data in the datapath when
// we change state).

    reg                         data_count_processed_run          = 1'b0;
    reg                         data_count_processed_load         = 1'b0;
    wire [DATA_COUNT_WIDTH-1:0] data_count_processed_remaining;

    Counter_Binary
    #(
        .WORD_WIDTH     (DATA_COUNT_WIDTH),
        .INCREMENT      (DATA_COUNT_ONE),
        .INITIAL_COUNT  (DATA_COUNT_ZERO)
    )
    data_counter_processed
    (
        .clock          (clock),
        .clear          (clear),

        .up_down        (1'b1), // 0/1 --> up/down
        .run            (data_count_processed_run),

        .load           (data_count_processed_load),
        .load_count     (data_count_load_value),

        .carry_in       (1'b0),
        // verilator lint_off PINCONNECTEMPTY
        .carry_out      (),
        .carries        (),
        .overflow       (),
        // verilator lint_on  PINCONNECTEMPTY

        .count          (data_count_processed_remaining)
    );

//### States

    localparam STATE_BITS   = 3;
    localparam EMPTY        = 3'd0; // Before first configuration.          Cannot load initial data.
    localparam IDLE         = 3'd1; // Waiting to load initial data.        Configuration can change.
    localparam LOAD         = 3'd2; // Loading initial data set into FIFO.  Configuration cannot change until IDLE again.
    localparam FIFO         = 3'd3; // Run the iterations with feedback from the FIFO output
    localparam MODULE       = 3'd4; // Run the iterations with feedback from the MODULE output
    localparam OUTPUT       = 3'd5; // Run the last iteration WITHOUT feedback, feeding the output

    wire [STATE_BITS-1:0] state;
    reg  [STATE_BITS-1:0] state_next = EMPTY;

    Register
    #(
        .WORD_WIDTH     (STATE_BITS),
        .RESET_VALUE    (EMPTY)
    )
    state_storage
    (
        .clock          (clock),
        .clock_enable   (1'b1),
        .clear          (clear),
        .data_in        (state_next),
        .data_out       (state)
    );

//### Input and Control Arbitration

// We have to disallow a simultaneous update of the control and the first
// input data load, otherwise we have to deal with very complicated corner
// cases, mostly around updating the counters. 

// So, when IDLE, if there is a simultaneous control and input handshake, let
// the control one finish first, then the input one, at which point we are in
// LOAD state, and no control handshake can happen.

// We do all this by arbitrating the incoming valid signals, then the rest of
// the control logic doesn't have to consider the order of control and input
// handshakes. *NOTE: this only works because a control handshake always only
// takes a single cycle to do its work.* 

// But because of the arbiter, we have to then gate off control handshakes
// when not IDLE or EMPTY, else a pending control handshake (raising valid)
// in other states (like LOAD) will block the input handshakes forever,
// preventing the LOAD state from completing and hanging the Iterator.

    reg                         gate_control_handshake = 1'b0;
    wire                        control_valid_gated;
    reg                         control_ready_gated = 1'b0;

    localparam CONTROL_GATE_WIDTH = ITER_COUNT_WIDTH + DATA_COUNT_WIDTH + 1;

    Pipeline_Gate
    #(
        .WORD_WIDTH     (CONTROL_GATE_WIDTH),
        .IMPLEMENTATION ("AND"),
        .GATE_DATA      (0)
    )
    gate_control
    (
        .enable         (gate_control_handshake == 1'b0),

        .input_valid    (control_valid),
        .input_ready    (control_ready),
        .input_data     ({iteration_count, data_count, feedback_type}),

        .output_valid   (control_valid_gated),
        .output_ready   (control_ready_gated),
        .output_data    ({iteration_count_gated, data_count_gated, feedback_type_gated})
    );

    wire control_valid_arbitrated;

    Arbiter_Priority
    #(
        .INPUT_COUNT    (2)
    )
    control_goes_first
    (
        .clock          (clock),
        .clear          (clear),

        .requests       ({input_valid, control_valid_gated}),
        .requests_mask  (2'b11), // Set to all-ones if unused.
        // verilator lint_off PINCONNECTEMPTY
        .grant_previous (),
        // verilator lint_on  PINCONNECTEMPTY
        .grant          ({input_valid_arbitrated, control_valid_arbitrated})
    );

    always @(*) begin
        control_ready_gated    = (state == EMPTY) || (state == IDLE);
        gate_control_handshake = (control_ready_gated == 1'b0);
    end

//### Datapath Operations

// These are the points in the pipeline we monitor to count the number of data
// items passing through.

    reg control_handshake_done          = 1'b0;
    reg input_handshake_done            = 1'b0;
    reg from_fifo_handshake_done        = 1'b0;
    reg module_feedback_handshake_done  = 1'b0;

    always @(*) begin
        control_handshake_done          = (control_valid_arbitrated == 1'b1) && (control_ready_gated    == 1'b1); // At control interface
        input_handshake_done            = (input_valid_arbitrated   == 1'b1) && (input_ready            == 1'b1); // At input selector external input: count initial FIFO load
        from_fifo_handshake_done        = (fifo_valid_gated         == 1'b1) && (fifo_ready_gated       == 1'b1); // At FIFO output, before fork: count words sent to module, and fed back to FIFO
        module_feedback_handshake_done  = (module_fork_valid        == 1'b1) && (module_fork_ready      == 1'b1); // At MODULE feedback fork: count words from module output, and fed back to FIFO, and to output on final iteration,
    end

//### Datapath Transformations

// These are events defined as happening in given states and depending on datapath
// states (counters, flags, etc...)

    reg config_zero                 = 1'b0; // Configuration being loaded contains a zero data count and/or a zero iteration count. **This halts the module.**

    reg load_config_zero            = 1'b0; // Loading a configuration with a zero data and/or iteration count, which disables data loads until a reconfiguration.
    reg load_config_first           = 1'b0; // Initial (no-zero) configuration. Cannot load data until configured.
    reg load_config                 = 1'b0; // Change (no-zero) configuration between runs. Has priority over a concurrent data load. 

    reg load_data_first             = 1'b0; // Load first word into FIFO, when there is more than one data item.
    reg load_data_output            = 1'b0; // Load only one word into FIFO, for one iteration, without feedback.
    reg load_data_fifo              = 1'b0; // Load only one word into FIFO, for multiple iterations, feeding back FIFO output to FIFO.
    reg load_data_module            = 1'b0; // Load only one word into FIFO, for multiple iterations, fedding back MODULE output to FIFO.

    reg load_data                   = 1'b0; // Load a word into the FIFO, while more words remain to be loaded.
    reg load_data_last_output       = 1'b0; // Load last word into FIFO, for one iteration, without feedback.
    reg load_data_last_fifo         = 1'b0; // Load last word into FIFO, for multiple iterations, feeding back FIFO output to FIFO.
    reg load_data_last_module       = 1'b0; // Load last word into FIFO, for multiple iterations, feeding back MODULE output to FIFO.

    reg run_fifo                    = 1'b0; // Send a word from the FIFO to the module, feed FIFO output back into FIFO
    reg run_fifo_processed          = 1'b0; // Word output by module, feed FIFO output back into FIFO.
    reg run_fifo_iter_processed     = 1'b0; // Receive last word of this iteration from the module, feed FIFO output back into FIFO, next iteration starts
    reg run_fifo_last_processed     = 1'b0; // Receive last word of this iteration from the module, feed FIFO output back into FIFO, last iteration starts

    reg run_module                  = 1'b0; // Send a word from the FIFO to the module, feed MODULE output back into FIFO
    reg run_module_processed        = 1'b0; // Receive a word from the module, feed MODULE output back into FIFO
    reg run_module_iter_processed   = 1'b0; // Receive last word of this iteration from the module, feed MODULE output back into FIFO, next iteration starts
    reg run_module_last_processed   = 1'b0; // Receive last word of this iteration from the module, feed MODULE output back into FIFO, last iteration starts

    reg run_output                  = 1'b0; // Receive a word from the module, WITHOUT feedback into FIFO, for the last iteration
    reg run_output_last             = 1'b0; // Receive the last word from the module, WITHOUT feedback into FIFO, for the last iteration

    always @(*) begin
        config_zero                 = (iteration_count_gated == ITER_COUNT_ZERO) || (data_count_gated == DATA_COUNT_ZERO);

        load_config_zero            = ((state == EMPTY) || (state == IDLE)) && (control_handshake_done == 1'b1) && (config_zero == 1'b1);
        load_config_first           =  (state == EMPTY)                     && (control_handshake_done == 1'b1) && (config_zero == 1'b0);
        load_config                 =  (state == IDLE)                      && (control_handshake_done == 1'b1) && (config_zero == 1'b0);

        load_data_first             = (state == IDLE) && (input_handshake_done == 1'b1) && (data_count_remaining != DATA_COUNT_ONE);
        load_data_output            = (state == IDLE) && (input_handshake_done == 1'b1) && (data_count_remaining == DATA_COUNT_ONE) && (iteration_count_remaining == ITER_COUNT_ONE);
        load_data_fifo              = (state == IDLE) && (input_handshake_done == 1'b1) && (data_count_remaining == DATA_COUNT_ONE) && (iteration_count_remaining != ITER_COUNT_ONE) && (feedback_type_stored == FEEDBACK_FIFO);
        load_data_module            = (state == IDLE) && (input_handshake_done == 1'b1) && (data_count_remaining == DATA_COUNT_ONE) && (iteration_count_remaining != ITER_COUNT_ONE) && (feedback_type_stored == FEEDBACK_MODULE);

        load_data                   = (state == LOAD) && (input_handshake_done == 1'b1) && (data_count_remaining != DATA_COUNT_ONE);
        load_data_last_output       = (state == LOAD) && (input_handshake_done == 1'b1) && (data_count_remaining == DATA_COUNT_ONE) && (iteration_count_remaining == ITER_COUNT_ONE);
        load_data_last_fifo         = (state == LOAD) && (input_handshake_done == 1'b1) && (data_count_remaining == DATA_COUNT_ONE) && (iteration_count_remaining != ITER_COUNT_ONE) && (feedback_type_stored == FEEDBACK_FIFO);
        load_data_last_module       = (state == LOAD) && (input_handshake_done == 1'b1) && (data_count_remaining == DATA_COUNT_ONE) && (iteration_count_remaining != ITER_COUNT_ONE) && (feedback_type_stored == FEEDBACK_MODULE);

        run_fifo                    = (state == FIFO) && (from_fifo_handshake_done == 1'b1) && (data_count_remaining != DATA_COUNT_ZERO);
        run_fifo_processed          = (state == FIFO) && (module_feedback_handshake_done == 1'b1) && (data_count_processed_remaining != DATA_COUNT_ONE);
        run_fifo_iter_processed     = (state == FIFO) && (module_feedback_handshake_done == 1'b1) && (data_count_processed_remaining == DATA_COUNT_ONE) && (iteration_count_remaining != ITER_COUNT_TWO);
        run_fifo_last_processed     = (state == FIFO) && (module_feedback_handshake_done == 1'b1) && (data_count_processed_remaining == DATA_COUNT_ONE) && (iteration_count_remaining == ITER_COUNT_TWO);

        run_module                  = (state == MODULE) && (from_fifo_handshake_done == 1'b1) && (data_count_remaining != DATA_COUNT_ZERO);
        run_module_processed        = (state == MODULE) && (module_feedback_handshake_done == 1'b1) && (data_count_processed_remaining != DATA_COUNT_ONE);
        run_module_iter_processed   = (state == MODULE) && (module_feedback_handshake_done == 1'b1) && (data_count_processed_remaining == DATA_COUNT_ONE) && (iteration_count_remaining != ITER_COUNT_TWO);
        run_module_last_processed   = (state == MODULE) && (module_feedback_handshake_done == 1'b1) && (data_count_processed_remaining == DATA_COUNT_ONE) && (iteration_count_remaining == ITER_COUNT_TWO);

        // Always on the last iteration (ITER_COUNT_ONE)
        run_output                  = (state == OUTPUT) && (module_feedback_handshake_done == 1'b1) && (data_count_processed_remaining != DATA_COUNT_ONE);
        run_output_last             = (state == OUTPUT) && (module_feedback_handshake_done == 1'b1) && (data_count_processed_remaining == DATA_COUNT_ONE);
    end

//### State Transitions

// Based on the datapath transformations, move from state to state. Each line
// represents an edge between states.

    always @(*) begin
        state_next = (load_config_zero          == 1'b1) ? EMPTY    : state;
        state_next = (load_config_first         == 1'b1) ? IDLE     : state_next;
        state_next = (load_config               == 1'b1) ? IDLE     : state_next;

        state_next = (load_data_first           == 1'b1) ? LOAD     : state_next; // Priority: control, then data, by external arbiter
        state_next = (load_data_output          == 1'b1) ? OUTPUT   : state_next;
        state_next = (load_data_fifo            == 1'b1) ? FIFO     : state_next;
        state_next = (load_data_module          == 1'b1) ? MODULE   : state_next;

        state_next = (load_data                 == 1'b1) ? LOAD     : state_next;
        state_next = (load_data_last_output     == 1'b1) ? OUTPUT   : state_next;
        state_next = (load_data_last_fifo       == 1'b1) ? FIFO     : state_next;
        state_next = (load_data_last_module     == 1'b1) ? MODULE   : state_next;

        state_next = (run_fifo_processed        == 1'b1) ? FIFO     : state_next;
        state_next = (run_fifo_iter_processed   == 1'b1) ? FIFO     : state_next;
        state_next = (run_fifo_last_processed   == 1'b1) ? OUTPUT   : state_next;

        state_next = (run_module_processed      == 1'b1) ? MODULE   : state_next;
        state_next = (run_module_iter_processed == 1'b1) ? MODULE   : state_next;
        state_next = (run_module_last_processed == 1'b1) ? OUTPUT   : state_next;

        state_next = (run_output                == 1'b1) ? OUTPUT   : state_next;
        state_next = (run_output_last           == 1'b1) ? IDLE     : state_next;
    end

//### Input Selection

// Depending on state, select what to feed the FIFO input.

    always @(*) begin
        input_select_one_hot = INPUT_SELECT_NONE; // EMPTY
        input_select_one_hot = (state == IDLE)   ? INPUT_SELECT_INPUT  : input_select_one_hot;
        input_select_one_hot = (state == LOAD)   ? INPUT_SELECT_INPUT  : input_select_one_hot;
        input_select_one_hot = (state == FIFO)   ? INPUT_SELECT_FIFO   : input_select_one_hot;
        input_select_one_hot = (state == MODULE) ? INPUT_SELECT_MODULE : input_select_one_hot;
        input_select_one_hot = (state == OUTPUT) ? INPUT_SELECT_NONE   : input_select_one_hot;
    end

//### Register Storage Control

// The control handshake is managed by arbitration logic further up.

    always @(*) begin
        feedback_type_store   = (control_handshake_done == 1'b1);
        iteration_count_store = (control_handshake_done == 1'b1); 
        data_count_store      = (control_handshake_done == 1'b1);
    end

//### Counter Control and Datapath Steering

// We break convention here for the sake of clarity and simply OR the signals
// together since we know they are all active-high and single bit.

// Decrement the counter by one, or load back the initial value from the
// storage registers.

    always @(*) begin
        data_count_run          = load_data_first  | load_data | run_fifo | run_module;
        data_count_load         = load_config_zero | load_config_first | load_config | load_data_last_output | load_data_last_fifo | load_data_last_module | run_fifo_iter_processed | run_fifo_last_processed | run_module_iter_processed | run_module_last_processed;
        data_count_load_initial = load_config_zero | load_config_first | load_config;
    end

    always @(*) begin
        data_count_processed_run  = run_fifo_processed | run_module_processed | run_output;
        data_count_processed_load = load_config_zero   | load_config_first    | load_config | run_fifo_iter_processed | run_fifo_last_processed | run_module_iter_processed | run_module_last_processed;
    end

    always @(*) begin
        iteration_count_run          = run_fifo_iter_processed | run_fifo_last_processed | run_module_iter_processed | run_module_last_processed;
        iteration_count_load         = load_config_zero | load_config_first | load_config | run_output_last;
        iteration_count_load_initial = load_config_zero | load_config_first | load_config;
    end

// Sink and gate paths on the pipeline to create the feedback we need, and to
// prevent loading data into later pipeline stages which would then buffer
// stale data which would be still present after shifting states, and corrupt
// later operations.

// NOTE: There's an implicit gating behaviour created here: we can chose to
// NOT sink a branch of a blocking fork in some cases, knowing that branch
// leads to an input of the input_selector which is not selected at that time,
// which will block that branch, and by extension, block the other branch of
// the blocking fork, creating a pipeline gate.

    always @(*) begin
        sink_fifo_feedback   = (state == MODULE) || (state == OUTPUT);      // Sink when feeding back module output or during final iteration.
        sink_module_feedback = (state != MODULE);                           // Sink when not feeding back module output.
        sink_output          = (state != OUTPUT);                           // Sink Iterator output when not in final iteration.
        gate_fifo_output     = (data_count_remaining == DATA_COUNT_ZERO);   // Gate the FIFO output once all data sent to module for the current iteration.
    end

endmodule

