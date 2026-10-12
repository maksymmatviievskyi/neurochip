import snn_pkg::*;

module motion_detector(
    input logic clk,
    input logic reset,
    input logic valid,
    input logic [MAX_NEURONS-1:0] spikes, // change to input layer size

    output logic motion
);

// 8 STEP delta encoding is ignored, as it will always fire at noise.
// True motion has to cross 32 STEP treshold


// Mask explanation: 1111 1111 1100   = 12'hFFC per axis ignores UP and DOWN bits for the smallest step (of 8)
// Hence for all axis:

localparam MASK = 36'hFFC_FFC_FFC;

always_ff @(posedge clk) begin
    if(reset) begin
        motion <= 0;
    end else begin
        motion <= |(spikes & MASK); // If any neuron spiked at higher steps -> classified as motion 
    end
end


endmodule