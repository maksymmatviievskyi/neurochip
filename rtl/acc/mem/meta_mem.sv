import snn_pkg::*;

module meta_mem (
    input logic clk,
    input logic wen,

    input logic [snn_pkg::LAYER_ADDR_W-1:0] raddr,
    input logic [snn_pkg::LAYER_ADDR_W-1:0] waddr,

    input logic [snn_pkg::CONN_ADDR_W-1:0]  wstart,
    input logic [snn_pkg::CONN_ADDR_W:0]    wcount,

    output logic [snn_pkg::CONN_ADDR_W-1:0] rstart,
    output logic [snn_pkg::CONN_ADDR_W:0]   rcount
);

    logic [snn_pkg::CONN_ADDR_W-1:0]
        start_mem [0:snn_pkg::MAX_LAYERS-1];

    logic [snn_pkg::CONN_ADDR_W:0]
        count_mem [0:snn_pkg::MAX_LAYERS-1];

    always_ff @(posedge clk) begin
        if (wen) begin
            start_mem[waddr] <= wstart;
            count_mem[waddr] <= wcount;
        end

        rstart <= start_mem[raddr];
        rcount <= count_mem[raddr];
    end

endmodule