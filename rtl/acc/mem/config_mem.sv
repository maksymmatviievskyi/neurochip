import snn_pkg::*;

module config_mem (
    input logic clk,
    input logic wen,

    input logic [snn_pkg::LAYER_ADDR_W-1:0] waddr,
    input logic [snn_pkg::LAYER_ADDR_W-1:0] raddr,

    input logic [snn_pkg::THRESHOLD_W-1:0]  wthreshold,
    input logic [snn_pkg::LEAK_SHIFT_W-1:0] wdecay,
    input logic [snn_pkg::THRESHOLD_W-1:0]  wreset,

    output logic [snn_pkg::THRESHOLD_W-1:0]  rthreshold,
    output logic [snn_pkg::LEAK_SHIFT_W-1:0] rdecay,
    output logic [snn_pkg::THRESHOLD_W-1:0]  rreset
);

    logic [snn_pkg::THRESHOLD_W-1:0]  threshold_mem [0:snn_pkg::MAX_LAYERS-1];
    logic [snn_pkg::LEAK_SHIFT_W-1:0] decay_mem     [0:snn_pkg::MAX_LAYERS-1];
    logic [snn_pkg::THRESHOLD_W-1:0]  reset_mem     [0:snn_pkg::MAX_LAYERS-1];

    always_ff @(posedge clk) begin
        if (wen) begin
            threshold_mem[waddr] <= wthreshold;
            decay_mem[waddr]     <= wdecay;
            reset_mem[waddr]     <= wreset;
        end

        rthreshold <= threshold_mem[raddr];
        rdecay     <= decay_mem[raddr];
        rreset     <= reset_mem[raddr];
    end

endmodule