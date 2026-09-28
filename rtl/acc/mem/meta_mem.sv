import snn_pkg::*;

module meta_mem #(
    parameter  int DEPTH   = MAX_LAYERS,
    parameter  int START_W = CONN_ADDR_W,
    parameter  int COUNT_W = CONN_ADDR_W + 1,
    localparam int ADDR_W  = (DEPTH <= 1) ? 1 : $clog2(DEPTH)
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

    logic [START_W-1:0] start_mem [0:DEPTH-1];
    logic [COUNT_W-1:0] count_mem [0:DEPTH-1];

    always_ff @(posedge clk) begin
        if (wen) begin
            start_mem[waddr] <= wstart;
            count_mem[waddr] <= wcount;
        end

        rstart <= start_mem[raddr];
        rcount <= count_mem[raddr];
    end

endmodule
