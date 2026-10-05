// Delta (level-crossing) encoder -- identical to snn/data.py::encode.
// One channel per (axis, step size); each channel keeps a reference value `ref`:
//     d = sample - ref;   d >= step: UP spike, ref += step;   d <= -step: DOWN spike, ref -= step
// At most one spike per channel per sample. `first` re-initialises every ref to the sample (no spikes).
// Output bit order matches data.channel(): axis * 2L + level * 2 + (0 = UP, 1 = DOWN).
module delta_encoder #(
    parameter int L = 6,
    parameter logic [16*L-1:0] STEPS = {16'd1000, 16'd400, 16'd150, 16'd60, 16'd25, 16'd10}  // level 0 in the low bits
) (
    input  logic               clk,
    input  logic               reset,
    input  logic               valid,
    input  logic               first,
    input  logic signed [15:0] x, y, z,
    output logic [6*L-1:0]     spikes,
    output logic               out_valid
);
    logic signed [17:0] ref_q [0:3*L-1];

    always_ff @(posedge clk) begin
        if (reset) begin
            out_valid <= 1'b0;
            spikes    <= '0;
            for (int c = 0; c < 3 * L; c++) ref_q[c] <= '0;
        end else begin
            out_valid <= valid;
            if (valid) begin
                for (int a = 0; a < 3; a++) begin
                    for (int l = 0; l < L; l++) begin
                        logic signed [17:0] s, st, d;
                        s  = (a == 0) ? 18'(x) : (a == 1) ? 18'(y) : 18'(z);
                        st = 18'($signed({1'b0, STEPS[16*l +: 16]}));
                        d  = s - ref_q[a*L + l];
                        if (first) begin
                            ref_q[a*L + l]       <= s;
                            spikes[a*2*L + 2*l]   <= 1'b0;
                            spikes[a*2*L + 2*l+1] <= 1'b0;
                        end else begin
                            spikes[a*2*L + 2*l]   <= (d >= st);
                            spikes[a*2*L + 2*l+1] <= (d <= -st);
                            if (d >= st)       ref_q[a*L + l] <= ref_q[a*L + l] + st;
                            else if (d <= -st) ref_q[a*L + l] <= ref_q[a*L + l] - st;
                        end
                    end
                end
            end
        end
    end
endmodule
