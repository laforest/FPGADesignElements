
//# Pulse to Pipeline Interface

// Wraps a module with an output pulse interface inside a ready/valid output
// handshake interface.  *The connected module must have at least one pipeline
// stage from input to output. No combinational paths allowed else the input
// and output handshake logic will form a loop.*

// When we have a module that cannot be fully pipelined due to a data
// dependency (e.g.: because of a backwards loop in the pipeline, or simply by
// the iterative nature of the implemented algorithm), and thus cannot accept
// a new input every cycle (i.e.: it has an initiation interval greater than
// 1), then we design the connected module to accept a new input with
// a one-cycle valid pulse, and to signal the updated output 1 or more cycles
// later with a corresponding one-cycle output pulse. 

// This Pulse to Pipeline module converts that output pulse interface into
// a pipeline output with a ready/valid handshake, and once read out, signals
// the corresponding input interface that new data can be accepted.

// Note that the connected module result can only be read out once, even if
// held steady until the next update. This is necessary to meet some Kahn
// Process Network criteria, and to allow for the connected module to use its
// output registers as part of its computations, rather than have extra
// buffers (which we instead hold here as the `output_buffer`).

// We assume here that the connected module is not C-Slowed, though that is
// allowed. You will have to keep track of the separate computation streams
// yourself in the enclosing module.

//## Choosing the Output Buffer Type

// An output buffer is necessary to cut the backwards combinational path from
// `ready_out` to `module_ready`, as well as to get the best performance and
// expected behaviour, depending on the connected module. Set
// `OUTPUT_BUFFER_TYPE` (and maybe `FIFO_BUFFER_DEPTH` and
// `FIFO_BUFFER_RAMSTYLE`) as required.

// * A **Skid Buffer** is generally the right choice: it allows the connected module
// to start a new computation while the `output_buffer` waits for the next
// pipeline stage to read out the previous result.
// * Use a **Half-Buffer** when the connected module should NOT be allowed to start
// a new computation until the previous result has been read out of the
// `output_buffer`. 
// * Use a **FIFO Buffer** when the later pipeline stages read in a bursty
// pattern, so the connected module can get through multiple computations in
// the meantime.

`default_nettype none

module Pulse_to_Pipeline
#(
    parameter WORD_WIDTH            = 0,
    parameter OUTPUT_BUFFER_TYPE    = "", // "HALF", "SKID", "FIFO"
    parameter FIFO_BUFFER_DEPTH     = 0,  // Only for "FIFO"
    parameter FIFO_BUFFER_RAMSTYLE  = ""  // Only for "FIFO"
)
(
    input   wire                        clock,
    input   wire                        clear,

    // Pipeline output
    output  wire                        valid_out,
    input   wire                        ready_out,
    output  wire    [WORD_WIDTH-1:0]    data_out,

    // Pulse interface from connected module
    input   wire    [WORD_WIDTH-1:0]    module_data_out,
    input   wire                        module_data_out_valid,

    // Signal that the module can accept the next input
    output  reg                         module_ready
);

    initial begin
        module_ready = 1'b0;
    end

// Express the usual conditions to complete a ready/valid handshake.  The
// "internal" signals connect to a Skid Buffer that deals with the final
// output handshake to the downstream pipeline. When we have transferred the
// module's output data to the Skid Buffer, we signal the module is ready for
// the next input.

    reg  valid_out_internal     = 1'b0;
    wire ready_out_internal;
    reg  output_handshake_done  = 1'b0;

    always @(*) begin
        output_handshake_done   = (valid_out_internal == 1'b1) && (ready_out_internal == 1'b1);
        module_ready            = (output_handshake_done == 1'b1);
    end

// The output ready/valid handshake starts when the connected module updates
// its output data.

    wire valid_out_latched;

    Pulse_Latch
    #(
        .RESET_VALUE    (1'b0)
    )
    generate_valid_out_latched
    (
        .clock          (clock),
        .clear          (output_handshake_done),
        .pulse_in       (module_data_out_valid),
        .level_out      (valid_out_latched)
    );

// Pass the module pulse directly, and also latch it. This removes a cycle of
// latency and still allows the output handshake to complete later if the
// downstream logic is not ready.

    always @(*) begin
        valid_out_internal = (valid_out_latched == 1'b1) || (module_data_out_valid == 1'b1);
    end

// Buffer the output handshake to cut the backwards combinational path from
// `ready_out` to `module_ready`. A Half-Buffer blocks `module_ready` until it
// is read out. A Skid Buffer allows overlap by raising `module_ready` while
// holding 1 previous result, but holding 2 results will cause it to block.
// A FIFO buffer will allow overlap and hold up to `FIFO_BUFFER_DEPTH` values
// before blocking.

    generate

        if (OUTPUT_BUFFER_TYPE == "HALF") begin
            Pipeline_Half_Buffer
            #(
                .WORD_WIDTH (WORD_WIDTH)
            )
            output_buffer
            (
                .clock          (clock),
                .clear          (clear),

                .input_valid    (valid_out_internal),
                .input_ready    (ready_out_internal),
                .input_data     (module_data_out),

                .output_valid   (valid_out),
                .output_ready   (ready_out),
                .output_data    (data_out)
            );
        end
        else if (OUTPUT_BUFFER_TYPE == "SKID") begin
            Pipeline_Skid_Buffer
            #(
                .WORD_WIDTH (WORD_WIDTH)
            )
            output_buffer
            (
                .clock          (clock),
                .clear          (clear),

                .input_valid    (valid_out_internal),
                .input_ready    (ready_out_internal),
                .input_data     (module_data_out),

                .output_valid   (valid_out),
                .output_ready   (ready_out),
                .output_data    (data_out)
            );
        end
        else if (OUTPUT_BUFFER_TYPE == "FIFO") begin
            Pipeline_FIFO_Buffer
            #(
                .WORD_WIDTH (WORD_WIDTH),
                .DEPTH      (FIFO_BUFFER_DEPTH),
                .RAMSTYLE   (FIFO_BUFFER_RAMSTYLE)
            )
            output_buffer
            (
                .clock          (clock),
                .clear          (clear),

                .input_valid    (valid_out_internal),
                .input_ready    (ready_out_internal),
                .input_data     (module_data_out),

                .output_valid   (valid_out),
                .output_ready   (ready_out),
                .output_data    (data_out)
            );
        end

    endgenerate

endmodule

