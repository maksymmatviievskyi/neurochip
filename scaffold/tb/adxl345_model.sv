`timescale 1ns/1ps
// Behavioural ADXL345 for simulation: 4-wire SPI mode 3, register file, DATA_READY on INT1.
// Once POWER_CTL.measure is set, it publishes the next sample of SAMPLE_FILE every PERIOD_NS
// (x, y, z as one 48-bit hex word per line) and raises INT1 until the data registers are read.
module adxl345_model #(
    parameter      SAMPLE_FILE = "samples.hex",
    parameter int  N_SAMPLES   = 1024,
    parameter real PERIOD_NS   = 150000.0
) (
    input  logic cs_n, sclk, sdi,
    output logic sdo,
    output logic int1
);
  logic [7:0]  regs [0:63];
  logic [47:0] samples [0:N_SAMPLES-1];
  logic [7:0]  sh_in, sh_out, cmd;
  logic [5:0]  addr;
  integer bitn, byten, nwrites = 0, nreads = 0, published = 0;

  initial begin
    for (int i = 0; i < 64; i++) regs[i] = 0;
    regs[0] = 8'hE5; int1 = 0; sdo = 1'bz;
    $readmemh(SAMPLE_FILE, samples);
  end

  always @(negedge cs_n) begin bitn = 0; byten = 0; end
  always @(posedge cs_n) begin
    sdo = 1'bz;
    if (byten >= 7 && cmd[7] && cmd[5:0] == 6'h32) begin int1 = 0; nreads++; end
  end
  always @(negedge sclk) if (!cs_n) begin                       // drive on falling edge
    if (bitn == 0 && byten >= 1 && cmd[7]) sh_out = regs[addr];
    sdo = (byten >= 1 && cmd[7]) ? sh_out[7 - bitn] : 1'b0;
  end
  always @(posedge sclk) if (!cs_n) begin                       // sample on rising edge
    sh_in = {sh_in[6:0], sdi}; bitn++;
    if (bitn == 8) begin
      bitn = 0;
      if (byten == 0) begin cmd = sh_in; addr = sh_in[5:0]; end
      else begin
        if (!cmd[7]) begin regs[addr] = sh_in; nwrites++; end
        if (cmd[6]) addr++;
      end
      byten++;
    end
  end

  always begin
    #(PERIOD_NS);
    if (regs[8'h2D][3] && published < N_SAMPLES) begin
      {regs[8'h33], regs[8'h32]} = samples[published][47:32];   // x
      {regs[8'h35], regs[8'h34]} = samples[published][31:16];   // y
      {regs[8'h37], regs[8'h36]} = samples[published][15:0];    // z
      published++;
      int1 = 1;
    end
  end
endmodule
