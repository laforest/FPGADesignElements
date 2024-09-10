
//# Differential Input Deserializer with 1 to N Ratio

// Takes in a serial differential data stream, at single or double data rate,
// and deserialises it as parallel words of both positive and negative
// polarity.  The input delays on the negative and positive signal polarity
// can be individually adjusted for bit-alignment training, and the hardware
// can bitslip for word-alignment training. All training is done by external
// modules.

// As an example, a DDR data stream at a `clk_serial` of 300 MHz with
// a `clk_parallel` of 100 MHz implies a `DATA_WIDTH` of 6, and thus a ratio
// of 1:6.

//## Usage Notes

// **This module is specific to Series 7 AMD/Xilinx FPGAs.** Please refer to
// the "*7 Series FPGAs SelectIO Resources User Guide (UG471)*" for details.
// However, the architecture is the same for many other FPGAs, so you can
// alter this design to fit your needs. 

// All the `IDELAYE2` modules in an I/O Bank depend on one instance of the 
// [IDELAYCTRL](./IDELAYCTRL_Instance.html) 
// module to maintain delay calibration and both
// must know the `IODELAY_REFCLK_FREQUENCY` delay reference clock frequency.

// **NOTE: If you change `DATA_WIDTH`, then you must manually rewire the
// `datain_p_parallel` and `datain_n_parallel` outputs at the ISERDESE2
// module.** This is cleaner than trying to automate it, and will avoid
// generating warnings about unused wires.

// The serial data is in the `clk_serial` domain. All other control and data
// signals are in the `clk_parallel` domain.

//## Parameters and Ports

`default_nettype none

module Deserializer_Differential_1toN
#(
    // For the input buffer of each data line

    parameter IBUF_DIFF_TERM                = "",               // Differential Termination, "TRUE"/"FALSE" 
    parameter IBUF_LOW_PWR                  = "",               // Low power="TRUE", Highest performance="FALSE" 
    parameter IBUF_IOSTANDARD               = "",               // Specify the input I/O standard (e.g.: "LVDS_25")

    parameter IODELAY_REFCLK_FREQUENCY      = ""                // External IDELAYCTRL reference clock input frequency in MHz (190.0-210.0, 290.0-310.0) 
    parameter IODELAY_GROUP                 = "",               // Must match IODELAY_GROUP applied to IDELAYCTRL module in same I/O Bank.
    parameter IODELAY_HIGH_PERFORMANCE_MODE = "",               // Reduced jitter ("TRUE"), Reduced power ("FALSE"). The clock source should have the same setting.

    // For the SERDES hardware

    parameter DATA_RATE                     = "",               // "DDR" or "SDR".
    parameter DATA_WIDTH                    = 6,                // How many bits to deserialize into? Must be natively supported by SERDES hardware. (UPDATE PARALLEL DATA WIRING AT SERDES!)

    // Do not set at instantiation, except in Vivado IPI

    parameter TAP_COUNTER_WIDTH             = 5                // Hardcoded to match the IDELAY2 hardware. See UG471.
)
(
    input  wire                             clk_serial,         // High-speed I/O clock for incoming serial data (IO only)
    input  wire                             clk_parallel,       // "Low-speed" clock for outgoing parallel data and all control inputs
    input  wire                             reset_parallel,     // Asynchronous/Synchronous reset in clk_parallel domain

    input  wire                             datain_n,           // High-speed serial I/O data in
    input  wire                             datain_p,

    // Positive input delay and bitslip control

    input  wire                             incdec_p_enable,    // Enable increment/decrement of delay tap
    input  wire                             incdec_p,           // Increment (1) or decrement (0) delay tap 
    output wire     [TAP_COUNTER_WIDTH-1:0] tap_p_current,      // Current value of delay tap
    input  wire     [TAP_COUNTER_WIDTH-1:0] tap_p_load_value,   // New value of delay tap
    input  wire                             tap_p_load,         // Load new delay tap value
    input  wire                             datain_p_bitslip,   // Pulse to shift output word
    output wire     [DATA_WIDTH-1:0]        datain_p_parallel,  // Deserialized data in clk_parallel domain

    // Negative input delay and bitslip control

    input  wire                             incdec_n_enable,    // Enable increment/decrement of delay tap
    input  wire                             incdec_n,           // Increment (1) or decrement (0) delay tap 
    output wire     [TAP_COUNTER_WIDTH-1:0] tap_n_current,      // Current value of delay tap
    input  wire     [TAP_COUNTER_WIDTH-1:0] tap_n_load_value,   // New value of delay tap
    input  wire                             tap_n_load,         // Load new delay tap value
    input  wire                             datain_n_bitslip,   // Pulse to shift output word
    output wire     [DATA_WIDTH-1:0]        datain_n_parallel   // Deserialized data in clk_parallel domain
);

//## Input Buffering

// First, buffer the differential input using a buffer with differential
// outputs. Each output polarity will go through its own delay and
// deserializer.

    wire datain_p_buffered;
    wire datain_n_buffered;

    IBUFDS_DIFF_OUT
    #(
        .DIFF_TERM    (IBUF_DIFF_TERM), // Differential Termination, "TRUE"/"FALSE" 
        .IBUF_LOW_PWR (IBUF_LOW_PWR),   // Low power="TRUE", Highest performance="FALSE" 
        .IOSTANDARD   (IBUF_IOSTANDARD) // Specify the input I/O standard
    )
    diff_input_buffer
    (
        .I            (datain_p),             // Diff_p buffer input (connect directly to top-level port)
        .IB           (datain_n),             // Diff_n buffer input (connect directly to top-level port)
        .O            (datain_p_buffered),    // Buffer diff_p output
        .OB           (datain_n_buffered)     // Buffer diff_n output
    );

//## Input Delays

// Instantiate an input delay for the data. An external module will adjust the
// delay taps to centre the data bit inside the clock (bit-alignment). 

// All the `IDELAY2` blocks inside an I/O Bank *must* be associated with
// exactly one `IDELAYCTRL` block per I/O Bank by sharing the same
// `IODELAY_GROUP` attribute.

//### Input Delay (Positive)

    wire datain_p_delayed;

    (* IODELAY_GROUP = IODELAY_GROUP *) // Specifies group name for associated IDELAY2s/ODELAY2s and IDELAYCTRL

    IDELAYE2
    #(
        .CINVCTRL_SEL           ("FALSE"),                      // Enable dynamic clock inversion (FALSE, TRUE)
        .DELAY_SRC              ("IDATAIN"),                    // Delay input (IDATAIN, DATAIN)
        .HIGH_PERFORMANCE_MODE  (IODELAY_HIGH_PERFORMANCE_MODE), // Reduced jitter ("TRUE"), Reduced power ("FALSE")
        .IDELAY_TYPE            ("VAR_LOAD"),                   // FIXED, VARIABLE, VAR_LOAD, VAR_LOAD_PIPE
        .IDELAY_VALUE           (0),                            // Input delay tap setting (0-31)
        .PIPE_SEL               ("FALSE"),                      // Select pipelined mode, FALSE, TRUE
        .REFCLK_FREQUENCY       (IODELAY_REFCLK_FREQUENCY),     // IDELAYCTRL clock input frequency in MHz (190.0-210.0, 290.0-310.0).
        .SIGNAL_PATTERN         ("DATA")                        // DATA, CLOCK input signal
    )
    input_data_delay_p 
    (
        .CNTVALUEOUT            (tap_p_current),        // 5-bit output: Counter value output
        .DATAOUT                (datain_p_delayed),     // 1-bit output: Delayed data output
        .C                      (clk_parallel),         // 1-bit input: Clock input
        .CE                     (incdec_p_enable),      // 1-bit input: Active high enable increment/decrement input
        .CINVCTRL               (1'b0),                 // 1-bit input: Dynamic clock inversion input
        .CNTVALUEIN             (tap_p_load_value),     // 5-bit input: Counter value input
        .DATAIN                 (1'b0),                 // 1-bit input: Internal delay data input
        .IDATAIN                (datain_p_buffered),    // 1-bit input: Data input from the I/O
        .INC                    (incdec_p),             // 1-bit input: Increment / Decrement tap delay input
        .LD                     (tap_p_load),           // 1-bit input: Load IDELAY_VALUE input
        .LDPIPEEN               (1'b0),                 // 1-bit input: Enable PIPELINE register to load data input
        .REGRST                 (reset_parallel)        // 1-bit input: Active-high reset tap-delay input
    );

//### Input Delay (Negative)

    wire datain_n_delayed;

    (* IODELAY_GROUP = IODELAY_GROUP *) // Specifies group name for associated IDELAYs/ODELAYs and IDELAYCTRL

    IDELAYE2
    #(
        .CINVCTRL_SEL           ("FALSE"),                      // Enable dynamic clock inversion (FALSE, TRUE)
        .DELAY_SRC              ("IDATAIN"),                    // Delay input (IDATAIN, DATAIN)
        .HIGH_PERFORMANCE_MODE  (IODELAY_HIGH_PERFORMANCE_MODE), // Reduced jitter ("TRUE"), Reduced power ("FALSE")
        .IDELAY_TYPE            ("VAR_LOAD"),                   // FIXED, VARIABLE, VAR_LOAD, VAR_LOAD_PIPE
        .IDELAY_VALUE           (0),                            // Input delay tap setting (0-31)
        .PIPE_SEL               ("FALSE"),                      // Select pipelined mode, FALSE, TRUE
        .REFCLK_FREQUENCY       (IODELAY_REFCLK_FREQUENCY),     // IDELAYCTRL clock input frequency in MHz (190.0-210.0, 290.0-310.0).
        .SIGNAL_PATTERN         ("DATA")                        // DATA, CLOCK input signal
    )
    input_data_delay_n 
    (
        .CNTVALUEOUT            (tap_n_current),        // 5-bit output: Counter value output
        .DATAOUT                (datain_n_delayed),     // 1-bit output: Delayed data output
        .C                      (clk_parallel),         // 1-bit input: Clock input
        .CE                     (incdec_n_enable),      // 1-bit input: Active high enable increment/decrement input
        .CINVCTRL               (1'b0),                 // 1-bit input: Dynamic clock inversion input
        .CNTVALUEIN             (tap_n_load_value),     // 5-bit input: Counter value input
        .DATAIN                 (1'b0),                 // 1-bit input: Internal delay data input
        .IDATAIN                (datain_n_buffered),    // 1-bit input: Data input from the I/O
        .INC                    (incdec_n),             // 1-bit input: Increment / Decrement tap delay input
        .LD                     (tap_n_load),           // 1-bit input: Load IDELAY_VALUE input
        .LDPIPEEN               (1'b0),                 // 1-bit input: Enable PIPELINE register to load data input
        .REGRST                 (reset_parallel)        // 1-bit input: Active-high reset tap-delay input
    );

//## Input Deserializations

// Now, independently deserialize the positive and negative data. The
// `DATA_WIDTH` must be natively supported by the `ISERDESE2` block.

// **NOTE:** The parallel data is deserialized in bit-reverse order, so we
// wire up the `datain_p_parallel` outputs in reverse to compensate. **Also,
// if you alter the `DATA_WIDTH`, then you must manually adjust the wiring
// here.** This is clearer than trying to make some clever automatic re-wiring
// that would create warnings about unused wires, and is not something that
// changes in a design anyway.

//### Input Deserialization (Positive)

    ISERDESE2
    #(
        .DATA_RATE          (DATA_RATE),    // "DDR", "SDR"
        .DATA_WIDTH         (DATA_WIDTH),   // Parallel data width (2-8,10,14)
        .DYN_CLKDIV_INV_EN  ("FALSE"),      // Enable DYNCLKDIVINVSEL inversion (FALSE, TRUE)
        .DYN_CLK_INV_EN     ("FALSE"),      // Enable DYNCLKINVSEL inversion (FALSE, TRUE)
        // INIT_Q1 - INIT_Q4: Initial value on the Q outputs (0/1)
        .INIT_Q1            (1'b0),
        .INIT_Q2            (1'b0),
        .INIT_Q3            (1'b0),
        .INIT_Q4            (1'b0),
        .INTERFACE_TYPE     ("NETWORKING"), // MEMORY, MEMORY_DDR3, MEMORY_QDR, NETWORKING, OVERSAMPLE
        .IOBDELAY           ("BOTH"),       // NONE, BOTH, IBUF, IFD
        .NUM_CE             (1),            // Number of clock enables (1,2)
        .OFB_USED           ("FALSE"),      // Select OFB path (FALSE, TRUE)
        .SERDES_MODE        ("MASTER"),     // MASTER, SLAVE
        // SRVAL_Q1 - SRVAL_Q4: Q output values when SR is used (0/1)
        .SRVAL_Q1           (1'b0),
        .SRVAL_Q2           (1'b0),
        .SRVAL_Q3           (1'b0),
        .SRVAL_Q4           (1'b0)
    )
    input_data_serdes_p
    (
        // verilator lint_off PINCONNECTEMPTY
        .O                  (),             // 1-bit output: Combinatorial output
        // Q1 - Q8: 1-bit (each) output: Registered data outputs.
        // *** BIT-REVERSED ORDER! ***
        .Q1                 (datain_p_parallel[5]),     // Example wiring for DATA_WIDTH = 6.
        .Q2                 (datain_p_parallel[4]),
        .Q3                 (datain_p_parallel[3]),
        .Q4                 (datain_p_parallel[2]),
        .Q5                 (datain_p_parallel[1]),
        .Q6                 (datain_p_parallel[0]),
        .Q7                 (),
        .Q8                 (),
        // SHIFTOUT1, SHIFTOUT2: 1-bit (each) output: Data width expansion output ports
        .SHIFTOUT1          (),
        .SHIFTOUT2          (),
        // verilator lint_on PINCONNECTEMPTY
        // 1-bit input: The BITSLIP pin performs a Bitslip operation
        // synchronous to CLKDIV when asserted (active High). Subsequently,
        // the data seen on the Q1 to Q8 output ports will shift one position
        // every time Bitslip is invoked (DDR operation is different from SDR).
        .BITSLIP            (datain_p_bitslip),
        // CE1, CE2: 1-bit (each) input: Data register clock enable inputs
        .CE1                (1'b1),
        .CE2                (1'b1),
        .CLKDIVP            (1'b0),             // 1-bit input: TBD
        // Clocks: 1-bit (each) input: ISERDESE2 clock input ports
        .CLK                (clk_serial),       // 1-bit input: High-speed clock
        .CLKB               (~clk_serial),      // 1-bit input: High-speed secondary clock
        .CLKDIV             (clk_parallel),     // 1-bit input: Divided clock
        .OCLK               (1'b0),             // 1-bit input: High speed output clock used when INTERFACE_TYPE="MEMORY" 
        // Dynamic Clock Inversions: 1-bit (each) input: Dynamic clock inversion pins to switch clock polarity
        .DYNCLKDIVSEL       (1'b0),             // 1-bit input: Dynamic CLKDIV inversion
        .DYNCLKSEL          (1'b0),             // 1-bit input: Dynamic CLK/CLKB inversion
        // Input Data: 1-bit (each) input: ISERDESE2 data input ports
        .D                  (1'b0),             // 1-bit input: Data input
        .DDLY               (datain_p_delayed), // 1-bit input: Serial data from IDELAYE2
        .OFB                (1'b0),             // 1-bit input: Data feedback from OSERDESE2
        .OCLKB              (1'b0),             // 1-bit input: High speed negative edge output clock
        .RST                (reset_parallel),   // 1-bit input: Active high asynchronous reset
        // SHIFTIN1, SHIFTIN2: 1-bit (each) input: Data width expansion input ports
        .SHIFTIN1           (1'b0),
        .SHIFTIN2           (1'b0)
    );

//### Input Deserialization (Negative)

    ISERDESE2
    #(
        .DATA_RATE          (DATA_RATE),    // "DDR", "SDR"
        .DATA_WIDTH         (DATA_WIDTH),   // Parallel data width (2-8,10,14)
        .DYN_CLKDIV_INV_EN  ("FALSE"),      // Enable DYNCLKDIVINVSEL inversion (FALSE, TRUE)
        .DYN_CLK_INV_EN     ("FALSE"),      // Enable DYNCLKINVSEL inversion (FALSE, TRUE)
        // INIT_Q1 - INIT_Q4: Initial value on the Q outputs (0/1)
        .INIT_Q1            (1'b0),
        .INIT_Q2            (1'b0),
        .INIT_Q3            (1'b0),
        .INIT_Q4            (1'b0),
        .INTERFACE_TYPE     ("NETWORKING"), // MEMORY, MEMORY_DDR3, MEMORY_QDR, NETWORKING, OVERSAMPLE
        .IOBDELAY           ("BOTH"),       // NONE, BOTH, IBUF, IFD
        .NUM_CE             (1),            // Number of clock enables (1,2)
        .OFB_USED           ("FALSE"),      // Select OFB path (FALSE, TRUE)
        .SERDES_MODE        ("MASTER"),     // MASTER, SLAVE
        // SRVAL_Q1 - SRVAL_Q4: Q output values when SR is used (0/1)
        .SRVAL_Q1           (1'b0),
        .SRVAL_Q2           (1'b0),
        .SRVAL_Q3           (1'b0),
        .SRVAL_Q4           (1'b0)
    )
    input_data_serdes_n
    (
        // verilator lint_off PINCONNECTEMPTY
        .O                  (),             // 1-bit output: Combinatorial output
        // Q1 - Q8: 1-bit (each) output: Registered data outputs
        // *** BIT-REVERSED ORDER! ***
        .Q1                 (datain_n_parallel[5]),     // Example wiring for DATA_WIDTH = 6  
        .Q2                 (datain_n_parallel[4]),
        .Q3                 (datain_n_parallel[3]),
        .Q4                 (datain_n_parallel[2]),
        .Q5                 (datain_n_parallel[1]),
        .Q6                 (datain_n_parallel[0]),
        .Q7                 (),
        .Q8                 (),
        // SHIFTOUT1, SHIFTOUT2: 1-bit (each) output: Data width expansion output ports
        .SHIFTOUT1          (),
        .SHIFTOUT2          (),
        // verilator lint_on PINCONNECTEMPTY
        // 1-bit input: The BITSLIP pin performs a Bitslip operation
        // synchronous to CLKDIV when asserted (active High). Subsequently,
        // the data seen on the Q1 to Q8 output ports will shift one position
        // every time Bitslip is invoked (DDR operation is different from SDR).
        .BITSLIP            (datain_n_bitslip),
        // CE1, CE2: 1-bit (each) input: Data register clock enable inputs
        .CE1                (1'b1),
        .CE2                (1'b1),
        .CLKDIVP            (1'b0),             // 1-bit input: TBD
        // Clocks: 1-bit (each) input: ISERDESE2 clock input ports
        .CLK                (clk_serial),       // 1-bit input: High-speed clock
        .CLKB               (~clk_serial),      // 1-bit input: High-speed secondary clock
        .CLKDIV             (clk_parallel),     // 1-bit input: Divided clock
        .OCLK               (1'b0),             // 1-bit input: High speed output clock used when INTERFACE_TYPE="MEMORY" 
        // Dynamic Clock Inversions: 1-bit (each) input: Dynamic clock inversion pins to switch clock polarity
        .DYNCLKDIVSEL       (1'b0),             // 1-bit input: Dynamic CLKDIV inversion
        .DYNCLKSEL          (1'b0),             // 1-bit input: Dynamic CLK/CLKB inversion
        // Input Data: 1-bit (each) input: ISERDESE2 data input ports
        .D                  (1'b0),             // 1-bit input: Data input
        .DDLY               (datain_n_delayed), // 1-bit input: Serial data from IDELAYE2
        .OFB                (1'b0),             // 1-bit input: Data feedback from OSERDESE2
        .OCLKB              (1'b0),             // 1-bit input: High speed negative edge output clock
        .RST                (reset_parallel),   // 1-bit input: Active high asynchronous reset
        // SHIFTIN1, SHIFTIN2: 1-bit (each) input: Data width expansion input ports
        .SHIFTIN1           (1'b0),
        .SHIFTIN2           (1'b0)
    );
     
endmodule

