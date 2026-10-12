import snn_pkg::*;

// Global interface for the SNN accelerator FSM

//   KEY0        reset
//   HEX5..HEX0  "------" while classifying, then the class for HOLD_CYCLES, then "IdLE"
//   LEDR0       blinks while samples arrive (~0.8 Hz)    LEDR1  motion (stretched so it is visible)
//   LEDR2       classifying                              LEDR7..3 one-hot of the class shown
//   LEDR9       snn overrun (a sample arrived while the snn was still busy; sticky until reset)

module de10_top #(
    parameter int T           = 256,              // timesteps per classification
    parameter int Q           = 80,               // quiet samples, needed to make sure classifications do not overlap and vibrations do not impact the reading
    parameter int OUT_START   = 100,              // first output neuron, fixed, might cause trouble
    parameter int HOLD_CYCLES = 100_000_000       // 2 s at 50 MHz
) (
    input  logic       MAX10_CLK1_50,
    input  logic [1:0] KEY,
    output logic [9:0] LEDR,
    output logic [7:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5,

    output logic       GSENSOR_CS_N,
    output logic       GSENSOR_SCLK,
    output logic       GSENSOR_SDI,               // MOSI (4-wire SPI)
    input  logic       GSENSOR_SDO,               // MISO
    input  logic [2:1] GSENSOR_INT
);

// Global Clock
logic clk;
assign clk = MAX10_CLK1_50;

// Reset
logic [15:0] por_cnt  = '0;                       // initial values = power-up values on MAX 10
logic        por_done = 1'b0;
always_ff @(posedge clk) begin
    if (!por_done) begin
        por_cnt <= por_cnt + 1'b1;
        if (&por_cnt) por_done <= 1'b1;           // hold reset for 65536 cycles
    end
end

logic [1:0] key_s = 2'b00;                        // KEY0 is asynchronous and active LOW: synchronise
always_ff @(posedge clk) key_s <= {key_s[0], ~KEY[0]};

logic reset = 1'b1;
always_ff @(posedge clk) reset <= !por_done || key_s[1];

// sensor
logic signed [15:0] x, y, z;
logic               sample_valid;

master sensor (
    .clk          (clk),
    .reset        (reset),
    .miso         (GSENSOR_SDO),
    .int1         (GSENSOR_INT[1]),
    .sclk         (GSENSOR_SCLK),
    .mosi         (GSENSOR_SDI),
    .cs           (GSENSOR_CS_N),
    .x            (x),
    .y            (y),
    .z            (z),
    .sample_valid (sample_valid)
);

logic [MAX_NEURONS-1:0] spikesIn, spikesOut;
logic                   enc_valid, snn_init, snn_done, snn_ready, sr_busy, snn_err;
logic                   run;

spike_record #(.STEP_N(6), .DATA_W(16)) encoder (
    .clk          (clk),
    .reset        (reset),
    .sample_valid (sample_valid),
    .x            (x),
    .y            (y),
    .z            (z),
    .spikesIn     (spikesIn),
    .enc_valid    (enc_valid),
    .snn_init     (snn_init),
    .snn_done     (snn_done),
    .snn_ready    (snn_ready),
    .run          (run),
    .busy         (sr_busy),
    .err          (snn_err)
);

logic motion, tick;

motion_detector md (
    .clk    (clk),
    .reset  (reset),
    .valid  (enc_valid),
    .spikes (spikesIn),
    .motion (motion)
);

// motion is registered from spikesIn, so it is valid one cycle after enc_valid
always_ff @(posedge clk) tick <= reset ? 1'b0 : enc_valid;

logic snn_rst, count_clear, decide, busy;

gesture_ctrl #(.T(T), .Q(Q)) ctrl (
    .clk         (clk),
    .reset       (reset),
    .tick        (tick),
    .motion      (motion),
    .snn_ready   (snn_ready),
    .snn_done    (snn_done),
    .snn_rst     (snn_rst),
    .run         (run),
    .count_clear (count_clear),
    .decide      (decide),
    .busy        (busy)
);

logic [LAYER_ADDR_W:0] num_layers;

snn #(
    .CONN_FILE        ("conn.hex"),
    .NEURON_META_FILE ("nmeta.hex"),
    .LAYER_META_FILE  ("lmeta.hex"),
    .CONFIG_FILE      ("config.hex"),
    .NUM_LAYERS_INIT  (3)
) core (
    .clk                (clk),
    .reset              (reset || snn_rst),
    .init               (snn_init),
    .spikesIn           (spikesIn),

    // the memories are initialised from the files, so write ports unused (keeping them for now just in case)
    .config_wen         (1'b0),
    .config_waddr       ('0),
    .config_raddr       ('0),
    .config_wthreshold  ('0),
    .config_wdecay      ('0),
    .config_wreset      ('0),
    .config_wnum_layers ('0),
    .neuron_meta_wen    (1'b0),
    .neuron_meta_waddr  ('0),
    .neuron_meta_wstart ('0),
    .neuron_meta_wcount ('0),
    .layer_meta_wen     (1'b0),
    .layer_meta_waddr   ('0),
    .layer_meta_wstart  ('0),
    .layer_meta_wcount  ('0),
    .conn_wen           (1'b0),
    .conn_waddr         ('0),
    .conn_wdata         ('0),

    .spikesOut          (spikesOut),
    .snn_done           (snn_done),
    .ready              (snn_ready),
    .num_layers         (num_layers)
);

logic [2:0] cls;
logic       cls_valid, have_result;

class_counter #(.OUT_START(OUT_START), .N_OUT(5), .CNT_W(9)) counter (
    .clk         (clk),
    .reset       (reset),
    .clear       (count_clear),
    .en          (run),
    .step        (snn_done),
    .spikes      (spikesOut),
    .decide      (decide),
    .cls         (cls),
    .cls_valid   (cls_valid),
    .have_result (have_result)
);

localparam logic [26:0] HOLD = HOLD_CYCLES;
logic [26:0] hold;
always_ff @(posedge clk) begin
    if (reset)             hold <= '0;
    else if (cls_valid)    hold <= HOLD;
    else if (hold != 0)    hold <= hold - 1'b1;
end

logic [2:0] shown;
assign shown = (hold != 0 || cls_valid) ? cls : 3'd0;   // result for HOLD_CYCLES, then idle

class_display disp (
    .cls  (shown),
    .busy (busy || decide),                       // decide: the cycle before the result is latched
    .hex5 (HEX5), .hex4 (HEX4), .hex3 (HEX3), .hex2 (HEX2), .hex1 (HEX1), .hex0 (HEX0)
);

// LEDs
logic [8:0]  beat;
logic [22:0] motion_led;
always_ff @(posedge clk) begin
    if (reset) begin
        beat       <= '0;
        motion_led <= '0;
    end else begin
        if (sample_valid)       beat       <= beat + 1'b1;
        if (tick && motion)     motion_led <= '1;
        else if (motion_led != 0) motion_led <= motion_led - 1'b1;
    end
end

assign LEDR[0]   = beat[8];
assign LEDR[1]   = (motion_led != 0);
assign LEDR[2]   = busy;
assign LEDR[7:3] = (hold != 0 || cls_valid) ? (5'b1 << cls) : 5'b0;
assign LEDR[8]   = 1'b0;
assign LEDR[9]   = snn_err;

endmodule
