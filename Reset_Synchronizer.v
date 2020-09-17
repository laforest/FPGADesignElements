//# Reset Synchronizer 

// Filters an asynchronous reset signal so it can assert immediately and
// asynchronously, but can only release synchronously with a receiving clock
// (after 2 or 3 (plus `EXTRA_DEPTH`) cycles of latency), which avoids
// metastability issues should the reset release too close to the receiving
// clock edge.

// Set the `RESET_ACTIVE_STATE` parameter to the value of your reset when
// active (e.g.: 0 for active-low reset).

// If you are running near the speed or temperature limits of your silicon,
// you may have to add some extra synchronizer stages with the `EXTRA_DEPTH`
// parameter. Consult your datasheets.

//## Implementation

// This design combines the internals of a [CDC
// Synchronizer](./CDC_Synchronizer.html) and of a [Register with Asynchronous
// Reset](./Register_areset.html) (please see those modules for more
// background).  We cannot instantiate those modules here since we have to
// apply some attributes directly to `reg` values to make a good synchronizer,
// and the CDC Synchronizer module does not have a reset.

//## Usage Notes and Limitations

// Much like a CDC Synchronizer, you can only synchronize a given reset bit in
// one place, as two synchronizers fed by the same input may have different
// output latencies due to metastability. Also, feed the `reset_in` input
// directly from a register, as combinational logic glitches could trigger
// spurious resets. Finally, you cannot place any of the registers into I/O
// registers: they are too far away from the main logic fabric to make a good
// synchronizer.

// *Make sure no logic under asynchronous reset feeds logic which is not also
// under reset, else metastability may happen in the latter logic since the
// reset assertion is not synchronous to the clock.* If you need reset
// assertion to be synchronous, use a [CDC
// Synchronizer](./CDC_Synchronizer.html) instead.

// **Also, note that introducing an asynchronous reset, even with synchronized
// release, may prevent any register retiming from ocurring in connected
// logic.** Check your CAD tool results, and favour the plain [CDC
// Synchronizer](./CDC_Synchronizer.html) instead.

//## Use Cases

// * If your reset comes from an external pin, synchronize it to your system
// clock before using it. *You must make sure the external reset is not
// glitchy.*
// * If you have logic which spans two clock domains, synchronize the reset
// from the first clock domain, considered the primary reset, into the second
// clock domain. This will reset both domains together and release the reset
// synchronously in the second clock domain, avoiding metastability. *This
// assumes a ready/valid handshake when exchanging data across the clock
// domains.*
// * If you have I/O logic that is driven by an external data clock which may
// or may not be active, reset the I/O logic by synchronizing the system reset
// to the data clock: the I/O logic will stay in reset until the data clock
// becomes active. *This means the data clock must run for at least
// `3 + EXTRA_DEPTH` cycles before I/O transactions can begin.*

`default_nettype none

module Reset_Synchronizer
#(
    parameter EXTRA_DEPTH           = 0,
    parameter RESET_ACTIVE_STATE    = 2   // Must be 0 (active-low) or 1 (active-high)
)
(
    input   wire    receiving_clock,
    input   wire    reset_in,
    output  reg     reset_out
);

    initial begin
        reset_out = ~RESET_ACTIVE_STATE [0];
    end

//## Synchronizer Registers

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
            sync_reg [i] = ~RESET_ACTIVE_STATE [0];
        end
    end

//## Reset Logic

// Now, depending on the reset active state, we instantiate one of two cases,
// distinguished only by the active edge of the reset signal. (It's grotesque
// to have such code duplication, but it's the only way.)

// When `reset_in` is asserted (as specified in `RESET_ACTIVE_STATE`),
// asynchronously place all synchronizer registers in reset, which immediately
// asserts `reset_out`. Then, when `reset_in` is released, the synchronizer
// will synchronously release `reset_out` after `DEPTH` or `DEPTH + 1` cycles,
// depending on the metastability of the first `sync_reg` register.

// Finally, if `RESET_ACTIVE_STATE` is given a value other than 0 or 1, try to
// instantiate a non-existent module to force synthesis or simulation to fail
// immediately, with the instance name as the error message. It's ugly, but
// CAD tools usually ignore `$display()` and `$finish()` system functions
// during synthesis. 

// *We must have this failsafe, else an invalid `RESET_ACTIVE_STATE` parameter
// could leave `reset_out` always inactive, causing hard-to-find, intermittent
// bugs in the logic dependent on `reset_out`.* Note the use of the identity
// operator (`===`) instead of the equality operator (`==`), so a parameter
// containing an `X` value does not implicitly match zero/false.

    generate
        if (RESET_ACTIVE_STATE === 0) begin

            always @(posedge receiving_clock, negedge reset_in) begin
                if (reset_in == RESET_ACTIVE_STATE [0]) begin
                    for(i = 0; i < DEPTH; i = i+1) begin
                        sync_reg [i] <= RESET_ACTIVE_STATE [0];
                    end
                end
                else begin
                    sync_reg [0] <= ~RESET_ACTIVE_STATE [0];
                    for(i = 1; i < DEPTH; i = i+1) begin
                        sync_reg [i] <= sync_reg [i-1]; 
                    end
                end
            end

        end
        else if (RESET_ACTIVE_STATE === 1) begin

            always @(posedge receiving_clock, posedge reset_in) begin
                if (reset_in == RESET_ACTIVE_STATE [0]) begin
                    for(i = 0; i < DEPTH; i = i+1) begin
                        sync_reg [i] <= RESET_ACTIVE_STATE [0];
                    end
                end
                else begin
                    sync_reg [0] <= ~RESET_ACTIVE_STATE [0];
                    for(i = 1; i < DEPTH; i = i+1) begin
                        sync_reg [i] <= sync_reg [i-1]; 
                    end
                end
            end

        end
        else begin

            // verilator lint_off DECLFILENAME
            NonExistentModuleForErrorChecking ERROR_RESET_ACTIVE_STATE_MUST_BE_0_OR_1 ();
            // verilator lint_on  DECLFILENAME

        end
    endgenerate

    always @(*) begin
        reset_out = sync_reg [DEPTH-1];
    end

endmodule

