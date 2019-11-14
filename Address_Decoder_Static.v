
//# Address Decoder (Static)

// A flexible address decoder. Works for any address range at any starting
// point. The base and bound addresses are set as parameters, so the range is
// fixed. This decoder works by checking if the input address lies between the
// base and bound (inclusive) of a range by comparing against each possible
// address within the range, then outputs the OR-reduction of all these
// checks.

// But there are a couple of caveats: your CAD tool will have to create
// a little netlist for up to all 2^ADDR_WIDTH possible addresses, and store
// the matches into a vector of up to 2^ADDR_WIDTH bits long, depending on the
// base and bound addresses.  Elaborating and optimizing this logic can take
// a *very* long time and, as I understand it, Verilog implementations have
// a maximum vector width of a million or so, so this decoder will be likley
// unusable for address ranges more than 20 bits wide.

// Also, even if your CAD tool can handle wider vectors, because we use an
// integer as counter, this decoder cannot be guaranteed to work for address
// ranges exceeding 32 bits, depending on your Verilog implementation.

// **I do not recommend this implementation.** I include it because I have put
// it to good use inside a CPU for decoding register operands, and it might be
// a good choice for very small, fixed address ranges if your CAD tool cannot
// fully optimize the [Behavioural Address
// Decoder](./Address_Decoder_Behavioural.html).

`default_nettype none

module Address_Decoder_Static
#(
    parameter       ADDR_WIDTH          = 0,
    parameter       ADDR_BASE           = 0,
    parameter       ADDR_BOUND          = 0
)
(
    input   wire    [ADDR_WIDTH-1:0]    addr,
    output  reg                         hit
);

    localparam ADDR_COUNT = ADDR_BOUND - ADDR_BASE + 1;
    localparam COUNT_ZERO = {ADDR_COUNT{1'b0}};

    initial begin
        hit = 1'b0;
    end

    integer                     i;
    reg     [ADDR_COUNT-1:0]    per_addr_match = COUNT_ZERO;

// Check each address in base/bound range for match, and store it in a vector
// for later OR-reduction.  Note that we select only the bit range we need
// from the index `i` so it doesn't raise a width mismatch warning when
// compared to the input address.  This does mean problems if `ADDR_WIDTH` is
// greater than 32 bits.

    always @(*) begin
        for(i = ADDR_BASE; i <= ADDR_BOUND; i = i + 1) begin : addr_decode
            per_addr_match[i-ADDR_BASE] = (addr == i[ADDR_WIDTH-1:0]);
        end
    end

    always @(*) begin : is_hit
        hit = |per_addr_match;
    end 

endmodule

