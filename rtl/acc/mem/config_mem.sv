import snn_pkg::*;

module config_mem #(
    parameter        INIT_FILE = "", // untyped: Icarus cannot pass a parameter into a string-typed one
    parameter int    NUM_LAYERS_INIT = 2
) (
    input logic clk,
    input logic wen,

    input logic [snn_pkg::LAYER_ADDR_W-1:0] waddr,
    input logic [snn_pkg::LAYER_ADDR_W-1:0] raddr,

    input logic [snn_pkg::THRESHOLD_W-1:0]  wthreshold,
    input logic [snn_pkg::LEAK_SHIFT_W-1:0] wdecay,
    input logic [snn_pkg::THRESHOLD_W-1:0]  wreset,
    input logic [snn_pkg::LAYER_ADDR_W:0] wnum_layers, // Min 2

    output logic [snn_pkg::THRESHOLD_W-1:0]  rthreshold,
    output logic [snn_pkg::LEAK_SHIFT_W-1:0] rdecay,
    output logic [snn_pkg::THRESHOLD_W-1:0]  rreset,
    output logic [snn_pkg::LAYER_ADDR_W:0] num_layers = (snn_pkg::LAYER_ADDR_W+1)'(NUM_LAYERS_INIT)
);
    logic [2*snn_pkg::THRESHOLD_W+snn_pkg::LEAK_SHIFT_W-1:0] mem [0:snn_pkg::MAX_LAYERS-1];

    initial if (INIT_FILE != "") $readmemh(INIT_FILE, mem);

    always_ff @(posedge clk) begin
        if (wen) begin
            mem[waddr] <= {wthreshold, wdecay, wreset};
            num_layers <= wnum_layers;
        end
        {rthreshold, rdecay, rreset} <= mem[raddr];
    end

endmodule
