import snn_pkg::*;

// Counts the output spikes of each class over one classification window and picks the winner.
// Output neurons are one-hot coded
module class_counter #(
    parameter int OUT_START = 100,         // first output neuron = inputs + hidden (36 + 64) hardcoded for now, may cause inconsistent behaviour
    parameter int N_OUT     = 5,
    parameter int CNT_W     = 9            // counts up to T = 256
) (
    input  logic                   clk,
    input  logic                   reset,

    input  logic                   clear,
    input  logic                   en,     // count only while the window is open
    input  logic                   step,   // snn_done: spikes holds a finished timestep
    input  logic [MAX_NEURONS-1:0] spikes,
    input  logic                   decide, // latch the winner

    output logic [2:0]             cls,        // last result
    output logic                   cls_valid,
    output logic                   have_result
);

logic [CNT_W-1:0] counts [0:N_OUT-1];

// argmax 
logic [2:0]       best;
logic [CNT_W-1:0] best_cnt;
always_comb begin
    best     = '0;
    best_cnt = counts[0];
    for (int c = 1; c < N_OUT; c++)
        if (counts[c] > best_cnt) begin
            best     = 3'(c);
            best_cnt = counts[c];
        end
end

always_ff @(posedge clk) begin
    if (reset) begin
        for (int c = 0; c < N_OUT; c++) counts[c] <= '0;
        cls         <= '0;
        cls_valid   <= 1'b0;
        have_result <= 1'b0;
    end else begin
        cls_valid <= 1'b0;

        if (clear) begin
            for (int c = 0; c < N_OUT; c++) counts[c] <= '0;
        end else if (step && en) begin
            for (int c = 0; c < N_OUT; c++) counts[c] <= counts[c] + CNT_W'(spikes[OUT_START + c]);
        end

        if (decide) begin
            cls         <= best;
            cls_valid   <= 1'b1;
            have_result <= 1'b1;
        end
    end
end

endmodule
