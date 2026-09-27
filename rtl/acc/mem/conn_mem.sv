import snn_pkg::*;

module conn_mem (
    input  logic clk,
    input  logic wen,
    input  logic [CONN_ADDR_W-1:0] raddr,
    input  logic [CONN_ADDR_W-1:0] waddr,
    input  logic [CONN_W-1:0]      data,
    output logic [NEURON_ADDR_W-1:0]   rsource,
    output logic [NEURON_ADDR_W-1:0]   rdest,
    output logic signed [WEIGHT_W-1:0] rweight
);

    logic [NEURON_ADDR_W-1:0]   source      [0:MAX_CONNECTIONS-1];
    logic [NEURON_ADDR_W-1:0]   destination [0:MAX_CONNECTIONS-1];
    logic signed [WEIGHT_W-1:0] weight      [0:MAX_CONNECTIONS-1];

    always_ff @(posedge clk) begin
        if (wen) begin
            source[waddr]      <= data[CONN_W-1 -: NEURON_ADDR_W];
            destination[waddr] <= data[CONN_W-1-NEURON_ADDR_W -: NEURON_ADDR_W];
            weight[waddr]      <= data[WEIGHT_W-1:0];
        end

        rsource <= source[raddr];
        rdest   <= destination[raddr];
        rweight <= weight[raddr];
    end

endmodule
