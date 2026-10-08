`timescale 1ns/1ps
// System test: recorded accelerometer data -> fake ADXL345 -> de10_top.
// Checks every readout decision (time, class, winning count) against the Python integer model
// (expected.txt from snn/sim_vectors.py) and prints the class names the board would show.
module de10_top_tb;
  parameter SAMPLE_FILE = "samples.hex";
  parameter EXPECT_FILE = "expected.txt";
  parameter ROM_FILE    = "snn_rom.hex";
  parameter int N_SAMPLES = 1024;

  logic clk = 0; always #10 clk = ~clk;
  logic [1:0] KEY = 2'b11;
  wire  [9:0] LEDR; wire [7:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5;
  wire cs_n, sclk, mosi, miso; wire [2:1] gint;

  de10_top #(.ROM_FILE(ROM_FILE), .HOLD_CYCLES(1000)) dut (
    .MAX10_CLK1_50(clk), .KEY(KEY), .LEDR(LEDR),
    .HEX0(HEX0), .HEX1(HEX1), .HEX2(HEX2), .HEX3(HEX3), .HEX4(HEX4), .HEX5(HEX5),
    .GSENSOR_CS_N(cs_n), .GSENSOR_SCLK(sclk), .GSENSOR_SDI(mosi), .GSENSOR_SDO(miso), .GSENSOR_INT(gint));

  adxl345_model #(.SAMPLE_FILE(SAMPLE_FILE), .N_SAMPLES(N_SAMPLES)) sensor (
    .cs_n(cs_n), .sclk(sclk), .sdi(mosi), .sdo(miso), .int1(gint[1]));
  assign gint[2] = 1'b0;

  // 7-segment -> text
  function automatic logic [7:0] ch(input logic [7:0] s);
    case (~s[6:0])
      7'b0000000: ch = " "; 7'b1000000: ch = "-"; 7'b1110111: ch = "A"; 7'b1011110: ch = "d";
      7'b1111001: ch = "E"; 7'b1110110: ch = "H"; 7'b0110000: ch = "I"; 7'b1110101: ch = "K";
      7'b0111000: ch = "L"; 7'b1110011: ch = "P"; 7'b1101101: ch = "S"; 7'b1111000: ch = "t";
      default:    ch = "?";
    endcase
  endfunction
  wire [47:0] text = {ch(HEX5), ch(HEX4), ch(HEX3), ch(HEX2), ch(HEX1), ch(HEX0)};

  // expected decisions: "t cls top" per line
  integer fd, n_exp = 0, n_dec = 0, bad = 0, steps = 0;
  integer et [0:63], ec [0:63], ek [0:63];
  initial begin
    fd = $fopen(EXPECT_FILE, "r");
    while (!$feof(fd) && n_exp < 64) begin
      if ($fscanf(fd, "%d %d %d\n", et[n_exp], ec[n_exp], ek[n_exp]) == 3) n_exp++;
    end
    $fclose(fd);
  end

  always @(posedge clk) if (dut.snn_done) steps++;
  always @(posedge clk) if (dut.dec_valid) begin
    if (n_dec < n_exp && (steps - 1 != et[n_dec] || dut.dec_cls != ec[n_dec] || dut.dec_top != ek[n_dec])) begin
      bad++;
      $display("MISMATCH decision %0d: rtl t=%0d cls=%0d top=%0d   python t=%0d cls=%0d top=%0d",
               n_dec, steps - 1, dut.dec_cls, dut.dec_top, et[n_dec], ec[n_dec], ek[n_dec]);
    end
    n_dec++;
  end
  always @(posedge clk) if (dut.result_valid)
    $display("[%0.1f ms] gesture result: class %0d  HEX = \"%s\"", $realtime / 1e6, dut.result_cls, text);

  logic [47:0] last = 0;
  always @(posedge clk) if (text != last) begin
    last = text;
    $display("[%0.1f ms] HEX5..0 = \"%s\"", $realtime / 1e6, last);
  end

  initial begin
    wait (sensor.published == N_SAMPLES);
    wait (steps == N_SAMPLES);
    repeat (5000) @(posedge clk);
    $display("timesteps %0d  decisions rtl %0d python %0d  mismatches %0d  snn overrun %0d  sensor writes %0d",
             steps, n_dec, n_exp, bad, dut.snn_err, sensor.nwrites);
    if (bad == 0 && n_dec == n_exp && !dut.snn_err) $display("PASS"); else $display("FAIL");
    $finish;
  end
endmodule
