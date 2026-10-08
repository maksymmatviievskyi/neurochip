import snn_pkg::*;

// DE10-Lite live gesture classifier  [SCAFFOLD: written by Claude, not part of the main design]
//
//   ADXL345 --SPI--> master --x,y,z--> spike_record (dencode) --spikes--> snn --spikesOut--> readout --> HEX
//                                                                          ^
//                                                       snn_loader (weights from ROM, after reset)
//
//   KEY0        reset (reloads the network, re-configures the sensor)
//   HEX5..HEX0  gesture class: IdLE, L-tAP, H-tAP, d-tAP, SHAKE  ("------" while loading)
//               during a gesture the best class so far is shown; the result stays for HOLD_CYCLES
//   LEDR0       network loaded          LEDR1  blinks while samples arrive (~1 Hz)
//   LEDR2       gesture in progress     LEDR7..3 one-hot of the class shown
//   LEDR9       snn overrun: a sample arrived while the snn was still busy (sticky until reset)
module de10_top #(
    parameter      ROM_FILE    = "snn_rom.hex",
    parameter int  OUT_START   = 100,           // = inputs + hidden neurons (36 + 64)
    parameter int  N_OUT       = 5,
    parameter int  HOLD_CYCLES = 100_000_000    // 2 s at 50 MHz
) (
    input  logic       MAX10_CLK1_50,
    input  logic [1:0] KEY,
    output logic [9:0] LEDR,
    output logic [7:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5,

    output logic       GSENSOR_CS_N,
    output logic       GSENSOR_SCLK,
    output logic       GSENSOR_SDI,             // MOSI (4-wire SPI)
    input  logic       GSENSOR_SDO,             // MISO
    input  logic [2:1] GSENSOR_INT
);

logic clk;
assign clk = MAX10_CLK1_50;

// ---------------- reset: power-on + KEY0, synchronised ----------------
logic [15:0] por_cnt = '0;                      // power-on: hold reset for 65536 cycles
logic        por_done = 1'b0;
always_ff @(posedge clk) begin
    if (!por_done) begin
        por_cnt <= por_cnt + 1'b1;
        if (&por_cnt) por_done <= 1'b1;
    end
end

logic [1:0] key_s = 2'b00;                      // KEY0 is asynchronous: two flip-flops
always_ff @(posedge clk) key_s <= {key_s[0], ~KEY[0]};

logic reset;
always_ff @(posedge clk) reset <= !por_done || key_s[1];

// ---------------- sensor ----------------
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

// ---------------- network loader ----------------
logic        loaded;
logic [63:0] cmd;
logic        config_wen, layer_meta_wen, neuron_meta_wen, conn_wen;

snn_loader #(.ROM_FILE(ROM_FILE)) loader (
    .clk             (clk),
    .reset           (reset),
    .loaded          (loaded),
    .cmd             (cmd),
    .config_wen      (config_wen),
    .layer_meta_wen  (layer_meta_wen),
    .neuron_meta_wen (neuron_meta_wen),
    .conn_wen        (conn_wen)
);

// ---------------- encoder + timestep control ----------------
logic [MAX_NEURONS-1:0] spikesIn, spikesOut;
logic                   snn_init, snn_done, snn_busy, snn_err;
logic [LAYER_ADDR_W:0]  num_layers;

spike_record #(.STEP_N(6), .DATA_W(16)) encoder (
    .clk          (clk),
    .reset        (reset || !loaded),           // start only once the weights are in
    .sample_valid (sample_valid),
    .x            (x),
    .y            (y),
    .z            (z),
    .spikesIn     (spikesIn),
    .snn_init     (snn_init),
    .snn_done     (snn_done),
    .busy         (snn_busy),
    .err          (snn_err)
);

// ---------------- snn core ----------------
snn core (
    .clk                (clk),
    .reset              (reset),
    .init               (snn_init),
    .spikesIn           (spikesIn),

    .config_wen         (config_wen),
    .config_waddr       (cmd[48 +: LAYER_ADDR_W]),
    .config_raddr       ('0),
    .config_wthreshold  (cmd[47:32]),
    .config_wdecay      (cmd[31:28]),
    .config_wreset      (cmd[27:12]),
    .config_wnum_layers (cmd[LAYER_ADDR_W:0]),

    .neuron_meta_wen    (neuron_meta_wen),
    .neuron_meta_waddr  (cmd[48 +: NEURON_ADDR_W]),
    .neuron_meta_wstart (cmd[13 +: CONN_ADDR_W]),
    .neuron_meta_wcount (cmd[CONN_ADDR_W:0]),

    .layer_meta_wen     (layer_meta_wen),
    .layer_meta_waddr   (cmd[48 +: LAYER_ADDR_W]),
    .layer_meta_wstart  (cmd[8 +: NEURON_ADDR_W]),
    .layer_meta_wcount  (cmd[NEURON_ADDR_W:0]),

    .conn_wen           (conn_wen),
    .conn_waddr         (cmd[48 +: CONN_ADDR_W]),
    .conn_wdata         (cmd[CONN_W-1:0]),

    .spikesOut          (spikesOut),
    .snn_done           (snn_done),
    .num_layers         (num_layers)
);

// ---------------- readout ----------------
logic       dec_valid, in_event, result_valid;
logic [2:0] dec_cls, event_cls, result_cls;
logic [8:0] dec_top;

readout #(.OUT_START(OUT_START), .N_OUT(N_OUT), .W(256), .D(32)) rd (
    .clk          (clk),
    .reset        (reset),
    .step         (snn_done),
    .spikes       (spikesOut),
    .dec_valid    (dec_valid),
    .dec_cls      (dec_cls),
    .dec_top      (dec_top),
    .in_event     (in_event),
    .event_cls    (event_cls),
    .result_valid (result_valid),
    .result_cls   (result_cls)
);

// ---------------- what to show ----------------
localparam logic [26:0] HOLD = HOLD_CYCLES;
logic [26:0] hold;
logic [2:0]  shown;
always_ff @(posedge clk) begin
    if (reset)              hold <= '0;
    else if (result_valid)  hold <= HOLD;
    else if (hold != 0)     hold <= hold - 1'b1;
end

always_comb begin
    if (in_event)       shown = event_cls;      // live: best class of the gesture so far
    else if (hold != 0 || result_valid)
                        shown = result_cls;     // result of the last gesture
    else                shown = 3'd0;           // idle
end

class_display disp (
    .cls   (shown),
    .blank (!loaded),
    .hex5  (HEX5), .hex4 (HEX4), .hex3 (HEX3), .hex2 (HEX2), .hex1 (HEX1), .hex0 (HEX0)
);

// ---------------- LEDs ----------------
logic [8:0] beat;                               // 400 samples/s -> bit 8 toggles at ~0.8 Hz
always_ff @(posedge clk) begin
    if (reset)             beat <= '0;
    else if (sample_valid) beat <= beat + 1'b1;
end

assign LEDR[0]   = loaded;
assign LEDR[1]   = beat[8];
assign LEDR[2]   = in_event;
assign LEDR[7:3] = loaded ? (5'b1 << shown) : 5'b0;
assign LEDR[8]   = 1'b0;
assign LEDR[9]   = snn_err;

endmodule
