import snn_pkg::*;

module meta_mem #(
    parameter  int DEPTH   = MAX_LAYERS,
    parameter  int START_W = CONN_ADDR_W,
    parameter  int COUNT_W = CONN_ADDR_W + 1,
    parameter int ADDR_W  = (DEPTH <= 1) ? 1 : $clog2(DEPTH),

    parameter        INIT_FILE = ""  // untyped: Icarus cannot pass a parameter into a string-typed one
) (
    input logic clk,
    input logic wen,

    input logic [ADDR_W-1:0]  raddr,
    input logic [ADDR_W-1:0]  waddr,

    input logic [START_W-1:0] wstart,
    input logic [COUNT_W-1:0] wcount,

    output logic [START_W-1:0] rstart,
    output logic [COUNT_W-1:0] rcount
);
    logic [START_W+COUNT_W-1:0] mem [0:DEPTH-1];

    initial begin 
        if (INIT_FILE != "") $readmemh(INIT_FILE, mem);
    end

    always_ff @(posedge clk) begin
        if (wen) mem[waddr] <= {wcount, wstart};
        {rcount, rstart} <= mem[raddr];
    end

endmodule
