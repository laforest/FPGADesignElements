
//# Clock Domain Crossing (CDC) Synchronizer

// Use a synchronizer to convert changes in a signal in one clock domain into
// changes which are synchronous to another clock domain, while reducing the
// probability of metastable events propagating.

//## A Warning

// A synchronizer is a trivial circuit, but it breaks the conventions of
// synchronous logic while doing its best to contain the consequences. Thus,
// it is very easy to use a synchronizer incorrectly, leading to worse timing
// closure at best, or at worst intermittent circuit malfunctions which won't
// be visible (or even reproducible!) in simulations. We go over the necessary
// subtleties in the text and code below.

//## Relative Clock Frequency Constraints

// This synchronizer is the fundamental building block of all other CDC
// circuits, and it must be used under one major constraint to operate
// properly: Any change on the input signal must hold steady for a **minimum**
// of 1.5x longer than the period of the receiving clock to guarantee enough
// time for three receiving clock edges (posedge/negedge/posedge, or
// negedge/posedge/negedge) to pass, which guarantees that the input signal
// will be properly sampled by a posedge.

// Any less time, and the input signal could change back before it was sampled
// by the receiving clock. In other words, assuming single-cycle changes
// (pulses), the receiving clock domain can have a clock frequency of at most
// 0.66x that of the sending clock domain. For any higher receiving clock
// freqency, you must guarantee that the change on the input signal will last
// enough input clock cycles to be seen by at least three consecutive
// receiving clock edges.

// If you cannot guarantee the duration of a pulse and/or have no knowledge of
// the relative clock domain frequencies, use a [Pulse
// Synchronizer](CDC_Pulse_Synchronizer.html).

//## Single-Bit Synchronization Only

// Also, for reasons explained in [Basic Clock Domain Crossing
// Theory](./cdc.html), the latency of a CDC Synchronizer can vary between
// 2 and 3 cycles, depending on metastability events, and so **only one signal
// may be synchronized at each clock domain crossing**. Using multiple CDC
// Synchronizers in parallel is **not deterministic** as there is no guarantee
// they will all have the same latency.  If you need to pass multiple signals
// (e.g.: a bus), synchronize one signal in each direction as a ready/valid
// handshake.

//## Avoid Logic Glitches

// **You must feed a CDC Synchronizer directly from a register**, with no
// logic between it and the synchronizer. Otherwise, it's possible that
// multiple logic paths will converge to the synchronizer, and convergent
// logic can glitch when signals change state (we're not getting into that
// theory here).  Normally, a subsequent register will filter out such
// glitches since they settle long before the next clock edge. However,
// a synchronizer's unrelated and asynchronous receiving clock may just happen
// to sample the input when a glitch occurs, transforming that glitch into
// a real, and completely wrong, logic pulse in the receiving clock domain!

//## Not Usable as I/O Registers

// On an FPGA, you should not use an I/O register as one of the stages of
// a synchronizer: they are too far from the main logic fabric, and
// synchronizer registers must be as close together as possible (see [Basic
// Clock Domain Crossing Theory](./cdc.html)). Thus, your input or output must
// connect to a dedicated I/O register synchronous to the I/O clock, which in
// turn connects to a CDC synchronizer driven by the internal clock. **This
// extra I/O register also filters out any input glitches, as outlined
// above.**

`default_nettype none

module CDC_Synchronizer
#(
    parameter EXTRA_DEPTH = 0 // Must be 0 or greater
)
(
    input   wire    receiving_clock,
    input   wire    bit_in,
    output  reg     bit_out
);

// The minimum valid synchronizer depth is 2. Add more stages if the design
// requires it. This usually happens near the highest operating frequencies.
// Consult your device datasheets.

    localparam DEPTH = 2 + EXTRA_DEPTH;

// For Vivado, we must specify that the synchronizer registers should be
// placed close together (see: UG912), and to show up as part of MTBF reports.

// For Quartus, specify that these register must not be optimized (e.g. moved
// into the input register of a DSP or BRAM) and to mark them as composing
// a synchronizer (and so be placed close together).

    (* ASYNC_REG = "TRUE" *)
    (* PRESERVE *)
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION \"FORCED IF ASYNCHRONOUS\"" *)

    reg sync_reg [DEPTH-1:0];

    integer i;

    initial begin
        for(i=0; i < DEPTH; i=i+1) begin
            sync_reg [i] = 1'b0;
        end
    end

// Pass the bit through DEPTH registers into the receiving clock domain.
// Peel out the first iteration to avoid a -1 index.

    always @(posedge receiving_clock) begin
        sync_reg [0] <= bit_in;

        for(i = 1; i < DEPTH; i = i+1) begin: cdc_stages
            sync_reg [i] <= sync_reg [i-1]; 
        end
    end

    always @(*) begin
        bit_out = sync_reg [DEPTH-1];
    end

endmodule

