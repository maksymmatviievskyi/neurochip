`timescale 1ns/1ps

import snn_pkg::*;

module snn_tb;

    logic clk = 0;
    logic reset = 1;
    logic init = 0;
    logic [MAX_NEURONS-1:0] spikesIn = '0;
    logic [MAX_NEURONS-1:0] spikesOut;
    logic snn_done;
    logic [LAYER_ADDR_W:0] num_layers;

    logic config_wen = 0;
    logic [LAYER_ADDR_W-1:0] config_waddr;
    logic [THRESHOLD_W-1:0] config_wthreshold;
    logic [LEAK_SHIFT_W-1:0] config_wdecay;
    logic [THRESHOLD_W-1:0] config_wreset;
    logic [LAYER_ADDR_W:0] config_wnum_layers;

    logic neuron_meta_wen = 0;
    logic [NEURON_ADDR_W-1:0] neuron_meta_waddr;
    logic [CONN_ADDR_W-1:0] neuron_meta_wstart;
    logic [CONN_ADDR_W:0] neuron_meta_wcount;

    logic layer_meta_wen = 0;
    logic [LAYER_ADDR_W-1:0] layer_meta_waddr;
    logic [NEURON_ADDR_W-1:0] layer_meta_wstart;
    logic [NEURON_ADDR_W:0] layer_meta_wcount;

    logic conn_wen = 0;
    logic [CONN_ADDR_W-1:0] conn_waddr;
    logic [CONN_W-1:0] conn_wdata;

    snn dut (
        .clk(clk),
        .reset(reset),
        .init(init),
        .spikesIn(spikesIn),
        .config_wen(config_wen),
        .config_waddr(config_waddr),
        .config_raddr('0),
        .config_wthreshold(config_wthreshold),
        .config_wdecay(config_wdecay),
        .config_wreset(config_wreset),
        .config_wnum_layers(config_wnum_layers),
        .neuron_meta_wen(neuron_meta_wen),
        .neuron_meta_waddr(neuron_meta_waddr),
        .neuron_meta_wstart(neuron_meta_wstart),
        .neuron_meta_wcount(neuron_meta_wcount),
        .layer_meta_wen(layer_meta_wen),
        .layer_meta_waddr(layer_meta_waddr),
        .layer_meta_wstart(layer_meta_wstart),
        .layer_meta_wcount(layer_meta_wcount),
        .conn_wen(conn_wen),
        .conn_waddr(conn_waddr),
        .conn_wdata(conn_wdata),
        .spikesOut(spikesOut),
        .snn_done(snn_done),
        .num_layers(num_layers)
    );

    always #5 clk = ~clk;

    int n_layers;
    int rng_start [0:MAX_LAYERS-1];
    int rng_count [0:MAX_LAYERS-1];
    int thr [0:MAX_LAYERS-1];
    int dec [0:MAX_LAYERS-1];
    int rst [0:MAX_LAYERS-1];

    int c_src [$];
    int c_dst [$];
    int c_w [$];

    longint mV [0:MAX_NEURONS-1];
    longint acc [0:MAX_NEURONS-1];
    logic [MAX_NEURONS-1:0] m_out;

    int errors = 0;
    int checks = 0;
    int done_pulses = 0;

    always @(posedge clk) if (snn_done) done_pulses++;

    function automatic string spike_list(input logic [MAX_NEURONS-1:0] v);
        string s;
        s = "";
        for (int n = 0; n < MAX_NEURONS; n++) if (v[n]) s = {s, $sformatf("%0d ", n)};
        if (s.len() == 0) s = "none";
        return s;
    endfunction

    task automatic clear_network();
        n_layers = 0;
        c_src.delete();
        c_dst.delete();
        c_w.delete();
    endtask

    task automatic add_layer(input int start, input int count, input int threshold, input int decay, input int reset_value);
        rng_start[n_layers] = start;
        rng_count[n_layers] = count;
        thr[n_layers] = threshold;
        dec[n_layers] = decay;
        rst[n_layers] = reset_value;
        n_layers++;
    endtask

    task automatic connect(input int src, input int dst, input int w);
        c_src.push_back(src);
        c_dst.push_back(dst);
        c_w.push_back(w);
    endtask

    task automatic reset_dut();
        @(negedge clk);
        reset = 1;
        repeat (2) @(negedge clk);
        reset = 0;
        for (int n = 0; n < MAX_NEURONS; n++) mV[n] = 0;
    endtask

    task automatic load_network();
        int addr;
        int first;
        for (int l = 0; l < n_layers; l++) begin
            @(negedge clk);
            config_wen = 1;
            config_waddr = l;
            config_wthreshold = thr[l];
            config_wdecay = dec[l];
            config_wreset = rst[l];
            config_wnum_layers = n_layers;
            layer_meta_wen = 1;
            layer_meta_waddr = l;
            layer_meta_wstart = rng_start[l];
            layer_meta_wcount = rng_count[l];
        end
        @(negedge clk);
        config_wen = 0;
        layer_meta_wen = 0;
        addr = 0;
        for (int s = 0; s < MAX_NEURONS; s++) begin
            first = addr;
            for (int k = 0; k < c_src.size(); k++) begin
                if (c_src[k] == s) begin
                    @(negedge clk);
                    conn_wen = 1;
                    conn_waddr = addr;
                    conn_wdata = {NEURON_ADDR_W'(c_src[k]), NEURON_ADDR_W'(c_dst[k]), WEIGHT_W'(c_w[k])};
                    addr++;
                end
            end
            @(negedge clk);
            conn_wen = 0;
            neuron_meta_wen = 1;
            neuron_meta_waddr = s;
            neuron_meta_wstart = first;
            neuron_meta_wcount = addr - first;
        end
        @(negedge clk);
        neuron_meta_wen = 0;
        repeat (2) @(negedge clk);
    endtask

    task automatic model_timestep(input logic [MAX_NEURONS-1:0] spk_in);
        logic [MAX_NEURONS-1:0] cur;
        logic [MAX_NEURONS-1:0] nxt;
        longint vn;
        cur = spk_in;
        for (int l = 1; l < n_layers; l++) begin
            for (int n = 0; n < MAX_NEURONS; n++) acc[n] = 0;
            for (int k = 0; k < c_src.size(); k++) begin
                if (cur[c_src[k]] && c_src[k] >= rng_start[l-1] && c_src[k] < rng_start[l-1] + rng_count[l-1])
                    acc[c_dst[k]] += longint'($signed(c_w[k]));
            end
            nxt = '0;
            for (int n = rng_start[l]; n < rng_start[l] + rng_count[l]; n++) begin
                vn = mV[n] - (mV[n] >>> dec[l]) + acc[n];
                if (vn >= thr[l]) begin
                    nxt[n] = 1'b1;
                    mV[n] = rst[l];
                end else begin
                    mV[n] = vn;
                end
            end
            cur = nxt;
        end
        m_out = cur;
    endtask

    task automatic run_timestep(input string name, input logic [MAX_NEURONS-1:0] spk_in);
        int cycles;
        int pulses_before;
        int bad;
        longint v_dut;
        model_timestep(spk_in);
        pulses_before = done_pulses;
        @(negedge clk);
        spikesIn = spk_in;
        init = 1;
        @(negedge clk);
        init = 0;
        cycles = 0;
        while (!snn_done && cycles < 20000) begin
            @(negedge clk);
            cycles++;
        end
        repeat (3) @(negedge clk);
        bad = 0;
        checks++;
        if (cycles >= 20000) begin
            bad++;
            $display("  FAIL %s: never finished", name);
        end
        if (done_pulses - pulses_before != 1) begin
            bad++;
            $display("  FAIL %s: done pulsed %0d times", name, done_pulses - pulses_before);
        end
        if (spikesOut !== m_out) begin
            bad++;
            $display("  FAIL %s: spikesOut = %s, expected %s", name, spike_list(spikesOut), spike_list(m_out));
        end
        for (int l = 1; l < n_layers; l++) begin
            for (int n = rng_start[l]; n < rng_start[l] + rng_count[l]; n++) begin
                v_dut = longint'($signed(dut.lif.V[n]));
                if (v_dut !== mV[n]) begin
                    bad++;
                    if (bad <= 6) $display("  FAIL %s: V[%0d] = %0d, expected %0d", name, n, v_dut, mV[n]);
                end
            end
        end
        if (bad == 0) $display("  ok   %-10s %4d cycles, out: %s", name, cycles, spike_list(spikesOut));
        errors += bad;
    endtask

    function automatic logic [MAX_NEURONS-1:0] spikes_at(input int a, input int b = -1, input int c = -1,
                                                         input int d = -1, input int e = -1, input int f = -1);
        logic [MAX_NEURONS-1:0] v;
        v = '0;
        if (a >= 0) v[a] = 1'b1;
        if (b >= 0) v[b] = 1'b1;
        if (c >= 0) v[c] = 1'b1;
        if (d >= 0) v[d] = 1'b1;
        if (e >= 0) v[e] = 1'b1;
        if (f >= 0) v[f] = 1'b1;
        return v;
    endfunction

    initial begin
        $display("snn_tb: network A (input + 3 layers, fan-in, negative weights, idle spiker, output neuron 127)");
        clear_network();
        add_layer(0, 8, 100, 15, 0);
        add_layer(40, 8, 100, 2, 0);
        add_layer(60, 4, 90, 1, 0);
        add_layer(120, 8, 100, 1, -10);
        connect(0, 40, 120);
        connect(1, 40, 30);
        connect(2, 40, 40);
        connect(3, 41, 80);
        connect(4, 41, -50);
        connect(5, 41, 80);
        connect(7, 47, 60);
        connect(40, 60, 110);
        connect(40, 61, 40);
        connect(41, 61, 70);
        connect(41, 62, -30);
        connect(47, 63, 127);
        connect(60, 127, 200);
        connect(61, 126, 150);
        connect(61, 127, -20);
        connect(62, 120, 100);
        connect(63, 125, 120);
        connect(45, 47, 150);
        reset_dut();
        load_network();
        run_timestep("A t1", spikes_at(0, 6));
        run_timestep("A t2", '0);
        run_timestep("A t3", spikes_at(1, 2, 3, 4, 5, 7));
        run_timestep("A t4", spikes_at(7));
        run_timestep("A t5", spikes_at(0, 3, 5, 7));
        run_timestep("A t6", spikes_at(1, 2, 7));
        run_timestep("A t7", spikes_at(7));
        run_timestep("A t8", spikes_at(3, 5, 40, 45, 60, 63));

        $display("snn_tb: network B (input + 1 layer, inputs at the top of the address space, source neuron 127)");
        clear_network();
        add_layer(120, 8, 100, 15, 0);
        add_layer(0, 4, 100, 3, 0);
        connect(127, 0, 110);
        connect(127, 1, 50);
        connect(126, 1, 60);
        connect(120, 3, -5);
        connect(121, 2, 100);
        reset_dut();
        load_network();
        run_timestep("B t1", spikes_at(127));
        run_timestep("B t2", spikes_at(126, 127));
        run_timestep("B t3", '0);
        run_timestep("B t4", spikes_at(120, 121, 125, 127));
        run_timestep("B t5", spikes_at(126, 127));

        if (errors == 0) $display("snn_tb: PASS (%0d timesteps checked)", checks);
        else $display("snn_tb: FAIL (%0d errors over %0d timesteps)", errors, checks);
        $finish;
    end

endmodule
