import snn_pkg::*;

// Live gesture classification around the snn core.
//
//  1. LOAD     after reset, a ROM (weights from snn/export.py --rom) is replayed into the snn write ports.
//  2. TRIGGER  every sample is stored in a 512-entry ring buffer and fed to a one-step delta encoder
//              (TRIG_STEP) whose output is kept per sample. The first trigger at sample i >= PRE that lies
//              after the previous window starts a window [i - PRE, i - PRE + T) -- exactly data.hw_windows().
//              Classifying a window takes at most ~15 ms (6 samples), far less than the 512-sample buffer.
//  3. COLLECT  wait until the whole window is in the ring buffer.
//  4. RUN      reset the snn (clears membrane potentials), then for each of the T samples: delta-encode
//              (encoder re-initialised on the first sample, like data.encode on a crop), drive spikesIn,
//              pulse init, wait snn_done, add the output spikes to per-class counts.
//  5. DECIDE   class = output with the most spikes (ties -> lowest index, i.e. idle).
module snn_live #(
    parameter int    T         = 256,
    parameter int    PRE       = 100,
    parameter logic [15:0] TRIG_STEP = 16'd25,
    parameter int    L         = 6,
    parameter logic [16*L-1:0] STEPS = {16'd1000, 16'd400, 16'd150, 16'd60, 16'd25, 16'd10},
    parameter        ROM_FILE  = "load.hex",       // $readmemh path, relative to the Quartus project
    parameter int    ROM_DEPTH = 4096,
    parameter int    CLR_WAIT  = 200,          // > MAX_NEURONS cycles: LIF memory sweep after snn reset
    parameter int    MAX_OUT   = 8
) (
    input  logic               clk,
    input  logic               reset,
    input  logic               sample_valid,
    input  logic signed [15:0] x, y, z,
    output logic               loaded,
    output logic               busy,           // window being collected or classified
    output logic [2:0]         cls,
    output logic               cls_valid,      // 1-cycle pulse per classified window
    output logic [9*MAX_OUT-1:0] counts_flat,  // output spike counts of the last window
    output logic [31:0]        win_start       // sample index where the last window started
);
    // ---------------- snn core ----------------
    logic snn_rst, snn_init, snn_done;
    logic [MAX_NEURONS-1:0] spikes_in, spikes_out;
    logic [LAYER_ADDR_W:0] num_layers;
    logic config_wen, neuron_meta_wen, layer_meta_wen, conn_wen;
    logic [63:0] cmd;

    snn core (
        .clk(clk), .reset(reset | snn_rst), .init(snn_init), .spikesIn(spikes_in),
        .config_wen(config_wen), .config_waddr(cmd[48 +: LAYER_ADDR_W]), .config_raddr('0),
        .config_wthreshold(cmd[47:32]), .config_wdecay(cmd[31:28]), .config_wreset(cmd[27:12]),
        .config_wnum_layers(cmd[LAYER_ADDR_W:0]),
        .neuron_meta_wen(neuron_meta_wen), .neuron_meta_waddr(cmd[48 +: NEURON_ADDR_W]),
        .neuron_meta_wstart(cmd[13 +: CONN_ADDR_W]), .neuron_meta_wcount(cmd[CONN_ADDR_W:0]),
        .layer_meta_wen(layer_meta_wen), .layer_meta_waddr(cmd[48 +: LAYER_ADDR_W]),
        .layer_meta_wstart(cmd[8 +: NEURON_ADDR_W]), .layer_meta_wcount(cmd[NEURON_ADDR_W:0]),
        .conn_wen(conn_wen), .conn_waddr(cmd[48 +: CONN_ADDR_W]), .conn_wdata(cmd[CONN_W-1:0]),
        .spikesOut(spikes_out), .snn_done(snn_done), .num_layers(num_layers)
    );

    // ---------------- weight ROM ----------------
    // word 0: {count[15:0], out_start[7:0], n_out[7:0], 32'b0}
    // word k: {type[1:0], addr[13:0], payload[47:0]}  type 0 config, 1 layer meta, 2 neuron meta, 3 connection
    logic [63:0] rom [0:ROM_DEPTH-1];
    logic [63:0] rom_q;
    logic [$clog2(ROM_DEPTH)-1:0] rom_addr;
    initial $readmemh(ROM_FILE, rom);
    always_ff @(posedge clk) rom_q <= rom[rom_addr];

    // ---------------- ring buffer of raw samples ----------------
    logic [47:0] ring [0:511];
    logic [47:0] ring_q;
    logic [8:0]  ring_raddr;
    logic [31:0] scount;                 // samples written since reset
    always_ff @(posedge clk) if (sample_valid) ring[scount[8:0]] <= {x, y, z};
    always_ff @(posedge clk) ring_q <= ring[ring_raddr];

    // ---------------- trigger ----------------
    logic [5:0]  trig_spk;
    logic        trig_valid;
    logic [31:0] last_idx;
    // one bit per sample: did the trigger encoder fire on it? Searched from next_allowed onwards, so a
    // trigger that happens while a window is being classified is not lost (same result as Python).
    logic        trig_hist [0:511];
    logic [31:0] tcount;                 // samples whose trigger bit is written
    logic [31:0] sp;                     // next sample to check for a trigger
    always_ff @(posedge clk) if (trig_valid) trig_hist[last_idx[8:0]] <= |trig_spk;

    delta_encoder #(.L(1), .STEPS(TRIG_STEP)) trig_enc (
        .clk(clk), .reset(reset), .valid(sample_valid), .first(scount == 0), .x(x), .y(y), .z(z),
        .spikes(trig_spk), .out_valid(trig_valid)
    );

    // ---------------- window encoder ----------------
    logic        enc_valid, enc_first, enc_out_valid;
    logic [6*L-1:0] enc_spk;
    delta_encoder #(.L(L), .STEPS(STEPS)) win_enc (
        .clk(clk), .reset(reset), .valid(enc_valid), .first(enc_first),
        .x(ring_q[47:32]), .y(ring_q[31:16]), .z(ring_q[15:0]),
        .spikes(enc_spk), .out_valid(enc_out_valid)
    );

    // ---------------- control ----------------
    typedef enum logic [3:0] { LD_HDR, LD_HDR_W, LD_RD, LD_WR, LD_CLR, IDLE, COLLECT,
                               CLR_RST, CLR_W, RD_ADDR, RD_DATA, ENC, WAIT_DONE, DECIDE } state_t;
    state_t state;

    logic [15:0] n_cmd, k;
    logic [7:0]  out_start;
    logic [3:0]  n_out;
    logic [8:0]  counts [0:MAX_OUT-1];
    logic [8:0]  i;
    logic [31:0] wstart;
    logic [7:0]  wait_cnt;

    always_comb for (int c = 0; c < MAX_OUT; c++) counts_flat[9*c +: 9] = counts[c];
    assign busy = (state == COLLECT) || (state >= CLR_RST && state <= DECIDE);

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= LD_HDR; rom_addr <= '0; loaded <= 1'b0;
            config_wen <= 0; neuron_meta_wen <= 0; layer_meta_wen <= 0; conn_wen <= 0;
            snn_rst <= 0; snn_init <= 0; enc_valid <= 0; enc_first <= 0;
            scount <= '0; tcount <= '0; sp <= PRE; last_idx <= '0;
            cls <= '0; cls_valid <= 1'b0; win_start <= '0; spikes_in <= '0;
            for (int c = 0; c < MAX_OUT; c++) counts[c] <= '0;
        end else begin
            config_wen <= 0; neuron_meta_wen <= 0; layer_meta_wen <= 0; conn_wen <= 0;
            snn_rst <= 0; snn_init <= 0; enc_valid <= 0; cls_valid <= 0;

            // sample bookkeeping and trigger (runs in every state)
            if (sample_valid) begin
                last_idx <= scount;
                scount   <= scount + 1'b1;
            end
            if (trig_valid) tcount <= tcount + 1'b1;

            case (state)
                // ---- load network from ROM ----
                LD_HDR:   state <= LD_HDR_W;                         // rom_addr = 0
                LD_HDR_W: begin
                    n_cmd <= rom_q[63:48]; out_start <= rom_q[47:40]; n_out <= rom_q[35:32];
                    k <= 16'd1; rom_addr <= 1; state <= LD_RD;
                end
                LD_RD:    state <= LD_WR;                            // ROM latency
                LD_WR: begin
                    cmd <= rom_q;
                    case (rom_q[63:62])
                        2'd0: config_wen      <= 1'b1;
                        2'd1: layer_meta_wen  <= 1'b1;
                        2'd2: neuron_meta_wen <= 1'b1;
                        2'd3: conn_wen        <= 1'b1;
                    endcase
                    if (k == n_cmd) begin wait_cnt <= '0; state <= LD_CLR; end
                    else begin k <= k + 1'b1; rom_addr <= rom_addr + 1'b1; state <= LD_RD; end
                end
                LD_CLR: begin                                        // let the last write land
                    wait_cnt <= wait_cnt + 1'b1;
                    if (wait_cnt == 8'd4) begin loaded <= 1'b1; state <= IDLE; end
                end

                // ---- wait for a gesture ----
                IDLE: if (sp < tcount) begin                         // one history entry per cycle
                    if (trig_hist[sp[8:0]]) begin
                        wstart <= sp - PRE;
                        sp     <= sp - PRE + T;                      // next trigger only after this window
                        state  <= COLLECT;
                    end else sp <= sp + 1'b1;
                end
                COLLECT: if (scount >= wstart + T) state <= CLR_RST;

                // ---- classify the window ----
                CLR_RST: begin snn_rst <= 1'b1; wait_cnt <= '0; state <= CLR_W; end
                CLR_W: begin
                    wait_cnt <= wait_cnt + 1'b1;
                    if (wait_cnt == CLR_WAIT[7:0]) begin
                        i <= '0;
                        for (int c = 0; c < MAX_OUT; c++) counts[c] <= '0;
                        state <= RD_ADDR;
                    end
                end
                RD_ADDR: begin ring_raddr <= 9'(wstart + i); state <= RD_DATA; end
                RD_DATA: state <= ENC;                               // ring_q valid next cycle
                ENC: begin
                    enc_valid <= 1'b1; enc_first <= (i == 0);
                    state <= WAIT_DONE;
                end
                WAIT_DONE: begin
                    if (enc_out_valid) begin
                        spikes_in <= {{(MAX_NEURONS - 6*L){1'b0}}, enc_spk};
                        snn_init  <= 1'b1;
                    end
                    if (snn_done) begin
                        for (int c = 0; c < MAX_OUT; c++)
                            if (c < n_out) counts[c] <= counts[c] + spikes_out[out_start + c];
                        if (i == T - 1) state <= DECIDE;
                        else begin i <= i + 1'b1; state <= RD_ADDR; end
                    end
                end
                DECIDE: begin
                    logic [2:0] best;
                    best = '0;
                    for (int c = 1; c < MAX_OUT; c++)
                        if (c < n_out && counts[c] > counts[best]) best = 3'(c);
                    cls <= best; cls_valid <= 1'b1; win_start <= wstart;
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
