// Used to make syn/power/power_vcd.zip: RTL simulation of power_tb.sv, VCD of 20 ms after the 12 ms boot.
// iverilog -g2012 -P de10_top_tb.SAMPLE_FILE=\"idle.hex\" -P dumper.CASE=\"idle\" <rtl files> ../adxl345_model.sv power_tb.sv rtl_vcd_dump.sv
module dumper;
  parameter string CASE = "idle";
  initial begin
    #12000000;                                   // skip 12 ms boot, like power.do
    $dumpfile({CASE, ".vcd"});
    $dumpvars(0, de10_top_tb.dut);
    #20000000;                                   // 20 ms = 8 samples
    $dumpflush;
    $display("%s: LEDR=%b shown=%0d err=%b", CASE, de10_top_tb.LEDR, de10_top_tb.dut.shown, de10_top_tb.dut.snn_err);
    $finish;
  end
endmodule
