// ADXL345 reader: SPI master pipeline
module master #(
    parameter int DATA_W = 16
) (
    input  logic clk,
    input  logic reset,

    // Sensor pins
    input  logic miso,              // GSENSOR_SDO
    input  logic int1,              // GSENSOR_INT[1], asynchronous (synchronised in seq)
    output logic sclk,              // GSENSOR_SCLK
    output logic mosi,              // GSENSOR_SDI
    output logic cs,                // GSENSOR_CS_N, active LOW

    // Samples
    output logic signed [DATA_W-1:0] x,
    output logic signed [DATA_W-1:0] y,
    output logic signed [DATA_W-1:0] z,
    output logic                     sample_valid
);

// Internal wiring
logic [7:0]  tx_byte;
logic [7:0]  rx_byte;
logic        start;
logic        done;
logic        byte_assmbl_init;
logic [47:0] data;

seq sq (
    .clk              (clk),
    .reset            (reset),
    .int1             (int1),
    .done             (done),
    .tx_byte          (tx_byte),
    .start            (start),
    .cs               (cs),
    .byte_assmbl_init (byte_assmbl_init)
);

spi sp (
    .miso          (miso),
    .clk           (clk),
    .reset         (reset),
    .transfer_init (start),
    .tx_byte       (tx_byte),
    .sclk          (sclk),
    .mosi          (mosi),
    .rx_byte       (rx_byte),
    .done          (done)
);

byte_assmbl ba (
    .done         (done),
    .clk          (clk),
    .reset        (reset),
    .init         (byte_assmbl_init),
    .rx_byte      (rx_byte),
    .sample_valid (sample_valid),
    .data         (data)
);

// Little endian: X0 X1 Y0 Y1 Z0 Z1
assign x = data[15:0];
assign y = data[31:16];
assign z = data[47:32];

endmodule
