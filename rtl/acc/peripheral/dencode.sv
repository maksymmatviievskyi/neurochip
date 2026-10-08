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

// Flat packed vector, step s = STEPS[16*s +: 16] (rightmost = step 0): portable to Quartus and Icarus
localparam logic [16*STEP_N-1:0] STEPS = {16'd1024, 16'd512, 16'd256, 16'd128, 16'd32, 16'd8};

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
                    int   st;                       // signed copy of the unsigned step
                    st   = STEPS[16*s +: 16];
                    up   = (d[a][s] >=  st);
                    down = (d[a][s] <= -st);
                    
                    if(up) begin 
                        mean[a][s] <= mean[a][s] + st;
                    end else if(down) begin 
                        mean[a][s] <= mean[a][s] - st;
                    end
                    spikes[2*(a*STEP_N+s) +: 2] <= {down, up}; // Assigns 2 spikes per channel
                end
            end
        end
    end
    done <= valid;
end
    
endmodule