import snn_pkg::*;

module lif_eng (
    input logic                         clk,
    input logic                         reset,
    input logic                         syn_ready,
    input logic [NEURON_ADDR_W-1:0] layer_range_start,
    input logic [NEURON_ADDR_W:0] layer_range_spread,
    input logic signed [I_W-1:0]     I [0:MAX_NEURONS-1],
    input logic [LEAK_SHIFT_W-1:0]           decay_shift, 
    input logic signed [THRESHOLD_W-1:0] threshold, 
    input logic signed [THRESHOLD_W-1:0] reset_value,
    output logic [MAX_NEURONS-1:0]      spikes
);

localparam int V_W = I_W + (2**LEAK_SHIFT_W - 1) + 1; // Extra safeguard bit added

logic signed [V_W:0] V [0:MAX_NEURONS-1];

always_ff @(posedge clk) begin
    if (reset) begin
        for (int i = 0; i < MAX_NEURONS; i++) begin
            V[i]     <= 0;
            spikes[i] <= 0;
        end 
    end else if (syn_ready) begin
        for (int i = 0; i < MAX_NEURONS; i++) begin
            if (i >= layer_range_start && i < layer_range_start + layer_range_spread) begin
                logic signed [V_W:0] VNXT;

                // Degrades decay precision
                // FEAT:  Change once floating operations are implemented
                VNXT = V[i] - (V[i] >>> decay_shift) + I[i];

                if (VNXT >= threshold) begin
                    spikes[i] <= 1;
                    V[i]     <= reset_value;
                end else begin
                    spikes[i] <= 0;
                    V[i]     <= VNXT;
                end
            end else begin
                spikes[i] <= 0;
            end
        end
    end
end

endmodule
