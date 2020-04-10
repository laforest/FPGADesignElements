
//# A Toggle Register

// A synchronous [Register](./Register.html) with a little extra logic to make
// it toggle. While `clock_enable` is high, each cycle `toggle` is high the
// output of the register will invert itself, regardless of the `data_in`
// input. If `toggle` is low, this module behaves like an ordinary register. 

//## How It Affects The Design Process

// It seems like overhead to have such trivial function as a distinct module,
// but if the extra 2:1 multiplexer and inverter on a feedback path from the
// output to the input was part of a larger circuit, its purpose would be
// obscured by other logic, or it would itself obscure the other logic. Thus,
// the user then has to reverse-engineer the implementation back to the
// intended function: a simple toggle, and further separate *that* function
// from the rest of the logic.

// It is much less mental effort to encounter a module that states "I am
// a toggle", which then makes the surrounding logic simpler and more
// meaningful. And because the initial design process and later comprehension
// of the design both need less mental effort, we can claim such a module fits
// our way of thinking and that we will very likely find a need for it in
// multiple future designs.

//## Function and Uses

// It is useful to imagine a toggle register, when holding a single bit, as
// a tiny finite state machine (FSM) with two states and transitions defined
// by the logic controlling the module inputs:

// * `clear`, to bring the FSM to the start state,
// * `clock_enable`, to control when transitions can happen,
// * `data_in`, to force the FSM into a given, *data-dependent* state,
// * `toggle`, to change to the other state without having to know which of
// the two states the FSM is currently in.

// Toggling can transform events denoted by the *presence* of a signal into
// events denoted by a *change* in a signal, such as when performing a 2-phase
// handshake between systems which are asynchronous to eachother. Or just to
// divide a pulse train by 2 or its multiples. Or by chaining multiple toggles
// to form a basic incrementing counter without using an adder, and so you can
// place logic between each counter bit to modulate it.

module Register_Toggle
#(
    parameter WORD_WIDTH  = 0,
    parameter RESET_VALUE = 0
)
(
    input   wire                        clock,
    input   wire                        clock_enable,
    input   wire                        clear,
    input   wire                        toggle,
    input   wire    [WORD_WIDTH-1:0]    data_in,
    output  wire    [WORD_WIDTH-1:0]    data_out
);

    reg [WORD_WIDTH-1:0] new_value = {WORD_WIDTH{1'b0}};

    Register
    #(
        .WORD_WIDTH     (WORD_WIDTH),
        .RESET_VALUE    (RESET_VALUE)
    )
    Register
    (
        .clock          (clock),
        .clock_enable   (clock_enable),
        .clear          (clear),
        .data_in        (new_value),
        .data_out       (data_out)
    );

    always @(*) begin
        new_value = (toggle == 1'b1) ? ~data_out : data_in;
    end

endmodule

