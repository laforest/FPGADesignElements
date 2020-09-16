//# Reset Synchronizer 

// Filters an asynchronous reset signal so it can assert immediately and
// asynchronously, but can only release synchronously with a clock (after 2 or
// 3 cycles of latency), which avoids metastability issues should the reset
// release too close to the clock edge.

// If you are running near the limits of your silicon, you may have to add
// some extra synchronizer stages: increment `EXTRA_DEPTH`

//## Implementation

// This design combines the internals of a [CDC
// Synchronizer](./CDC_Synchronizer.html) and of a [Register with Asynchronous
// Reset](./Register_areset.html) (please see those modules for more
// background).  We cannot instantiate those modules here since we have to
// apply some attributes directly to `reg` values to make a good synchronizer,
// and the existing CDC Synchronizer does not have a reset.

//## Usage Notes

// Much like a CDC Synchronizer, you can only synchronize a given reset bit in
// one place, as two synchronizers fed by the same input may have different
// output latencies due to metastability. Also, feed the `reset_in` input
// directly from a register, as combinational logic glitches could trigger
// suprious resets. Finally, you cannot place any of the registers as I/O
// registers: they are too far apart to make a good synchronizer.

`default_nettype none

module Reset_Synchronizer
#(
    parameter EXTRA_DEPTH           = 0,
    parameter RESET_ACTIVE_STATE    = 1'b0
)
(
    input   wire    clock,
    input   wire    reset_in,
    output  reg     reset_out
);

    initial begin
        reset_out = ~RESET_ACTIVE_STATE;
    end

// The minimum valid synchronizer depth is 2. Add more stages if the design
// requires it. This usually happens near the highest operating frequencies.
// Consult your device datasheets.

    localparam DEPTH = 2 + EXTRA_DEPTH;

// For Vivado, we must specify that the synchronizer registers should be
// placed close together (see: UG912), and to show up as part of MTBF reports.

// For Quartus, specify that these register must not be optimized (e.g. moved
// into the input register of a DSP or BRAM) and to mark them as composing
// a synchronizer (and so be placed close together).

// In both cases, we also specify that the registers must not be placed in I/O
// register locations.

    // Vivado
    (* IOB = "false" *)
    (* ASYNC_REG = "TRUE" *)

    // Quartus
    (* useioff = 0 *)
    (* PRESERVE *)
    (* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION \"FORCED IF ASYNCHRONOUS\"" *)

    reg sync_reg [DEPTH-1:0];

    integer i;

    initial begin
        for(i=0; i < DEPTH; i=i+1) begin
            sync_reg [i] = ~RESET_ACTIVE_STATE;
        end
    end

// Pass the bit through DEPTH registers into the receiving clock domain.
// Peel out the first iteration to avoid a -1 index.

    generate
        if (RESET_ACTIVE_STATE == 1'b0) begin
            always @(posedge clock, negedge reset_in) begin
                if (reset_in == RESET_ACTIVE_STATE) begin
                    for(i = 0; i < DEPTH; i = i+1) begin
                        sync_reg [i] <= RESET_ACTIVE_STATE;
                    end
                end
                else begin
                    sync_reg [0] <= ~RESET_ACTIVE_STATE;
                    for(i = 1; i < DEPTH; i = i+1) begin
                        sync_reg [i] <= sync_reg [i-1]; 
                    end
                end
            end
        end
        else if (RESET_ACTIVE_STATE == 1'b1) begin
            always @(posedge clock, posedge reset_in) begin
                if (reset_in == RESET_ACTIVE_STATE) begin
                    for(i = 0; i < DEPTH; i = i+1) begin
                        sync_reg [i] <= RESET_ACTIVE_STATE;
                    end
                end
                else begin
                    sync_reg [0] <= ~RESET_ACTIVE_STATE;
                    for(i = 1; i < DEPTH; i = i+1) begin
                        sync_reg [i] <= sync_reg [i-1]; 
                    end
                end
            end
        end
    endgenerate

    always @(*) begin
        reset_out = sync_reg [DEPTH-1];
    end

endmodule

