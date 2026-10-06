import snn_pkg::*;

module dencode #(
    parameter int STEP_N = 6,
    parameter int DATA_Q = 3,
    parameter int DATA_W = 16
    ) (
    input logic clk,
    input logic reset,
    input logic init,
    input logic valid,
    
    input logic signed [DATA_W-1:0] sample [0:DATA_Q-1],

    output logic [MAX_NEURONS-1:0] spikes,
    output logic done
);

// 2 overflow bits
logic signed [DATA_W+1:0] d    [DATA_Q][STEP_N];
logic signed [DATA_W+1:0] mean [DATA_Q][STEP_N];

localparam int STEPS [STEP_N] = '{8, 32, 128, 256, 512, 1024};

// Delta Calculations
always_comb begin
     for(int a = 0; a < DATA_Q; a++) begin
        for(int s = 0; s < STEP_N; s++) begin
            d[a][s] = sample[a] - mean[a][s];
        end
     end
end

// Parallel Compute
always_ff @(posedge clk) begin
    if(reset) begin
        done <= 0;
        spikes <= 0;
    end else if (valid) begin
        for(int a = 0; a < DATA_Q; a++) begin
            for(int s = 0; s < STEP_N; s++) begin
                if(init) begin 
                    mean[a][s] <= sample[a];
                    spikes <= 0;
                end else begin
                    logic up, down;
                    up   = (d[a][s] >=  STEPS[s]);
                    down = (d[a][s] <= -STEPS[s]);
                    
                    if(up) begin 
                        mean[a][s] <= mean[a][s] + STEPS[s];
                    end else if(down) begin 
                        mean[a][s] <= mean[a][s] - STEPS[s];
                    end
                    spikes[2*(a*STEP_N+s) +: 2] <= {down, up}; // Assigns 2 spikes per channel
                end
            end
        end
    end
    done <= valid;
end
    
endmodule