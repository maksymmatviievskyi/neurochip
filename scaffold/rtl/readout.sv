// [SCAFFOLD: written by Claude, not part of the main design]
import snn_pkg::*;

// Turns the output spikes of the snn into gesture classifications.
//
//  1. COUNT   after every snn timestep, add the output spikes to per-class counts that cover the last
//             W timesteps (a ring buffer remembers what to subtract when a timestep leaves the window).
//  2. DECIDE  every D timesteps: class = output with the most spikes (ties -> lowest index = idle).
//  3. EVENT   a gesture is a run of non-idle decisions. During the run, the decision with the highest
//             winning count is kept ("peak"); when the decisions return to idle, that class is the
//             result of the gesture (result_valid pulse). The peak is used because at the start and
//             the end of a gesture the window only sees part of it (e.g. one tap of a double tap).
module readout #(
    parameter int OUT_START = 100,          // first output neuron (index in spikesOut)
    parameter int N_OUT     = 5,            // number of classes, class 0 = idle
    parameter int W         = 256,          // counting window [timesteps], must be a power of 2
    parameter int D         = 32,           // decision period [timesteps]
    parameter int CNT_W     = $clog2(W) + 1
) (
    input  logic                   clk,
    input  logic                   reset,
    input  logic                   step,                // snn_done: one timestep finished
    input  logic [MAX_NEURONS-1:0] spikes,              // snn spikesOut

    // every decision (for debugging / testbench)
    output logic                   dec_valid,
    output logic [2:0]             dec_cls,
    output logic [CNT_W-1:0]       dec_top,

    // gesture events
    output logic                   in_event,            // a gesture is being seen right now
    output logic [2:0]             event_cls,           // best class so far in the current/last event
    output logic                   result_valid,        // 1-cycle pulse when a gesture ends
    output logic [2:0]             result_cls
);

localparam int PTR_W = $clog2(W);

// ---------------- sliding-window counts ----------------
logic [N_OUT-1:0] ring [0:W-1];
logic [N_OUT-1:0] old_q;                // ring entry that is about to leave the window
logic [N_OUT-1:0] new_s;
logic [PTR_W-1:0] wptr;
logic             filled;               // W timesteps seen: start subtracting
logic [CNT_W-1:0] counts [0:N_OUT-1];
logic [$clog2(D)-1:0] dcnt;
logic             decide;

assign new_s = spikes[OUT_START +: N_OUT];

always_ff @(posedge clk) begin
    if (step) ring[wptr] <= new_s;
    old_q <= ring[wptr];                // wptr is stable for thousands of cycles between steps
end

// ---------------- argmax (ties -> lowest index) ----------------
logic [2:0]       best;
logic [CNT_W-1:0] best_cnt;
always_comb begin
    best     = '0;
    best_cnt = counts[0];
    for (int c = 1; c < N_OUT; c++)
        if (counts[c] > best_cnt) begin
            best     = c[2:0];
            best_cnt = counts[c];
        end
end

logic [CNT_W-1:0] event_top;

always_ff @(posedge clk) begin
    if (reset) begin
        wptr         <= '0;
        filled       <= 1'b0;
        dcnt         <= '0;
        decide       <= 1'b0;
        dec_valid    <= 1'b0;
        dec_cls      <= '0;
        dec_top      <= '0;
        in_event     <= 1'b0;
        event_cls    <= '0;
        event_top    <= '0;
        result_valid <= 1'b0;
        result_cls   <= '0;
        for (int c = 0; c < N_OUT; c++) counts[c] <= '0;
    end else begin
        decide       <= 1'b0;
        dec_valid    <= 1'b0;
        result_valid <= 1'b0;

        // 1. COUNT
        if (step) begin
            for (int c = 0; c < N_OUT; c++)
                counts[c] <= counts[c] + new_s[c] - ((filled && old_q[c]) ? 1'b1 : 1'b0);
            wptr <= wptr + 1'b1;
            if (wptr == W - 1) filled <= 1'b1;
            dcnt <= dcnt + 1'b1;
            if (dcnt == D - 1) begin
                dcnt   <= '0;
                decide <= 1'b1;                     // counts are updated on the next cycle
            end
        end

        // 2. DECIDE + 3. EVENT
        if (decide) begin
            dec_valid <= 1'b1;
            dec_cls   <= best;
            dec_top   <= best_cnt;

            if (best != 0) begin
                if (!in_event || best_cnt > event_top) begin
                    event_cls <= best;
                    event_top <= best_cnt;
                end
                in_event <= 1'b1;
            end else if (in_event) begin
                in_event     <= 1'b0;
                event_top    <= '0;
                result_valid <= 1'b1;
                result_cls   <= event_cls;
            end
        end
    end
end

endmodule
