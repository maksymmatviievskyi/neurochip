`timescale 1ns/1ps
// Power-estimation testbench: drives ONLY the board pins, so it works with the gate-level netlist
// (simulation/modelsim/de10.vo) as well as with the RTL. Real timing: ADXL345 sample every 2.5 ms.
// The module is called de10_top_tb and the instance dut, so the Quartus setting
// "Design instance name" = de10_top_tb/dut matches the VCD that ModelSim writes.
module de10_top_tb;
  parameter SAMPLE_FILE = "shake.hex";        // idle.hex or shake.hex (x, y, z per line)

  logic clk = 0;
  always #10 clk = ~clk;                      // 50 MHz

  logic [1:0] KEY = 2'b11;                    // no button pressed (power-on reset is internal)
  wire  [9:0] LEDR;
  wire  [7:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5;
  wire        cs_n, sclk, mosi, miso;
  wire  [2:1] gint;

  de10_top dut (
    .MAX10_CLK1_50 (clk),
    .KEY           (KEY),
    .LEDR          (LEDR),
    .HEX0 (HEX0), .HEX1 (HEX1), .HEX2 (HEX2), .HEX3 (HEX3), .HEX4 (HEX4), .HEX5 (HEX5),
    .GSENSOR_CS_N  (cs_n),
    .GSENSOR_SCLK  (sclk),
    .GSENSOR_SDI   (mosi),
    .GSENSOR_SDO   (miso),
    .GSENSOR_INT   (gint)
  );

  adxl345_model #(.SAMPLE_FILE(SAMPLE_FILE), .N_SAMPLES(256), .PERIOD_NS(2_500_000.0)) sensor (
    .cs_n (cs_n), .sclk (sclk), .sdi (mosi), .sdo (miso), .int1 (gint[1])
  );
  assign gint[2] = 1'b0;

  // progress (run time is set by the .do script)
  always @(posedge gint[1]) if (sensor.published % 8 == 1)
    $display("[%0.1f ms] sample %0d  LEDR=%b", $realtime / 1e6, sensor.published, LEDR);
endmodule
