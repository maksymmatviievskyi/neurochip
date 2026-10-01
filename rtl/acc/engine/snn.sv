import snn_pkg::*;

module snn (
    input logic clk,
    input logic reset,
    input logic init,
    input logic [MAX_NEURONS-1:0] spikesIn,

    input logic config_wen,
    input logic [LAYER_ADDR_W-1:0] config_waddr,
    input logic [LAYER_ADDR_W-1:0] config_raddr,
    input logic [THRESHOLD_W-1:0] config_wthreshold,
    input logic [LEAK_SHIFT_W-1:0] config_wdecay,
    input logic [THRESHOLD_W-1:0] config_wreset,
    input logic [LAYER_ADDR_W:0] config_wnum_layers,

    input logic neuron_meta_wen,
    input logic [NEURON_ADDR_W-1:0] neuron_meta_waddr,
    input logic [CONN_ADDR_W-1:0] neuron_meta_wstart,
    input logic [CONN_ADDR_W:0] neuron_meta_wcount,

    input logic layer_meta_wen,
    input logic [LAYER_ADDR_W-1:0] layer_meta_waddr,
    input logic [NEURON_ADDR_W-1:0] layer_meta_wstart,
    input logic [NEURON_ADDR_W:0] layer_meta_wcount,

    input logic conn_wen,
    input logic [CONN_ADDR_W-1:0] conn_waddr,
    input logic [CONN_W-1:0] conn_wdata,
    output logic [MAX_NEURONS-1:0] spikesOut,
    output logic snn_done,
    output logic [LAYER_ADDR_W:0] num_layers
);
    // ---------------------- Definitions ----------------------

    typedef enum logic [1:0] { IDLE, SYN, LIF } state_t;
    state_t state;

    logic [MAX_NEURONS-1:0] spikesTemp;
    logic [MAX_NEURONS-1:0] spikesLIF;

    logic [NEURON_ADDR_W-1:0] neuron_meta_raddr;
    logic [CONN_ADDR_W-1:0] neuron_conn_start;
    logic [CONN_ADDR_W:0] neuron_conn_count;

    logic [LAYER_ADDR_W-1:0] layer_meta_raddr;
    logic [NEURON_ADDR_W-1:0] layer_neuron_start;
    logic [NEURON_ADDR_W:0] layer_neuron_count;

    logic [CONN_ADDR_W-1:0] conn_raddr;
    logic [NEURON_ADDR_W-1:0] conn_rsource;
    logic [NEURON_ADDR_W-1:0] conn_rdest;
    logic signed [WEIGHT_W-1:0] conn_rweight;

    logic syn_done;
    logic syn_init; 

    logic [THRESHOLD_W-1:0] layer_threshold;
    logic [LEAK_SHIFT_W-1:0] layer_decay;
    logic [THRESHOLD_W-1:0] layer_reset;

    logic [LAYER_ADDR_W-1:0] lcounter;
    logic [NEURON_ADDR_W-1:0] src_start;
    logic [NEURON_ADDR_W:0] src_count;
    assign layer_meta_raddr = lcounter;

     // ----------------------    Logic   ----------------------

     always_ff @(posedge clk) begin
        if(reset) begin
            state <= IDLE;
            snn_done <= 1'b0;
            syn_init <= 1'b0;
            lcounter <= '0;
            src_start <= '0;
            src_count <= '0;
        end else begin
            snn_done <= 1'b0;
            syn_init <= 1'b0;
            case (state)
                IDLE: begin
                    if (init) begin
                        src_start <= layer_neuron_start;
                        src_count <= layer_neuron_count;
                        lcounter <= 1;
                        spikesTemp <= spikesIn;
                        syn_init <= 1'b1;
                        state <= SYN;
                    end
                end
                SYN: begin
                    if (syn_done) state <= LIF;
                end
                LIF: begin
                    if (lcounter == num_layers - 1) begin
                        snn_done <= 1'b1;
                        spikesOut <= spikesLIF;
                        lcounter <= '0;
                        state <= IDLE;
                    end else begin
                        src_start <= layer_neuron_start;
                        src_count <= layer_neuron_count;
                        spikesTemp <= spikesLIF;
                        lcounter <= lcounter + 1;
                        syn_init <= 1'b1;
                        state <= SYN;
                    end
                end
                default: begin
                    state <= IDLE;
                end
            endcase
        end
     end

    logic signed [I_W-1:0] I [0:MAX_NEURONS-1];

    // ---------------------- Instantiantion ----------------------
    config_mem layer_config (
        .clk(clk),
        .wen(config_wen),
        .waddr(config_waddr),
        .raddr(lcounter),
        .wthreshold(config_wthreshold),
        .wdecay(config_wdecay),
        .wreset(config_wreset),
        .wnum_layers(config_wnum_layers),
        .rthreshold(layer_threshold),
        .rdecay(layer_decay),
        .rreset(layer_reset),
        .num_layers(num_layers)
    );

    meta_mem #(
        .DEPTH(MAX_NEURONS),
        .START_W(CONN_ADDR_W),
        .COUNT_W(CONN_ADDR_W + 1)
    ) neuron_conn_meta (
        .clk(clk),
        .wen(neuron_meta_wen),
        .raddr(neuron_meta_raddr),
        .waddr(neuron_meta_waddr),
        .wstart(neuron_meta_wstart),
        .wcount(neuron_meta_wcount),
        .rstart(neuron_conn_start),
        .rcount(neuron_conn_count)
    );

    meta_mem #(
        .DEPTH(MAX_LAYERS),
        .START_W(NEURON_ADDR_W),
        .COUNT_W(NEURON_ADDR_W + 1)
    ) layer_ranges (
        .clk(clk),
        .wen(layer_meta_wen),
        .raddr(layer_meta_raddr),
        .waddr(layer_meta_waddr),
        .wstart(layer_meta_wstart),
        .wcount(layer_meta_wcount),
        .rstart(layer_neuron_start),
        .rcount(layer_neuron_count)
    );

    conn_mem connections (
        .clk(clk),
        .wen(conn_wen),
        .raddr(conn_raddr),
        .waddr(conn_waddr),
        .data(conn_wdata),
        .rsource(conn_rsource),
        .rdest(conn_rdest),
        .rweight(conn_rweight)
    );

    lif_eng lif (
        .clk(clk),
        .reset(reset),
        .syn_ready(syn_done),
        .layer_range_start(layer_neuron_start),
        .layer_range_spread(layer_neuron_count),
        .I(I),
        .decay_shift(layer_decay),
        .threshold($signed(layer_threshold)),
        .reset_value($signed(layer_reset)),
        .spikes(spikesLIF)
    );

    syn_eng syn (
        .clk(clk),
        .reset(reset),
        .init(syn_init),
        .spikes(spikesTemp),
        .conn_meta_rstart(neuron_conn_start),
        .conn_meta_rcount(neuron_conn_count),
        .layer_range_rstart(src_start),
        .layer_range_rcount(src_count),
        .conn_rsource(conn_rsource),
        .conn_rdest(conn_rdest),
        .conn_rweight(conn_rweight),
        .layer_range_raddr(),
        .conn_meta_raddr(neuron_meta_raddr),
        .conn_raddr(conn_raddr),
        .I(I),
        .done(syn_done)
    );

endmodule

