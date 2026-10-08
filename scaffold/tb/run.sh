#!/bin/sh
# System test of the board design on one recorded window (fake ADXL345 -> de10_top), bit-exact vs Python.
#   cd scaffold/tb && sh run.sh ../snn/recordings/s2_double_tap.mif 1      (recording, window 0..15)
# Needs iverilog and the Python packages in scaffold/snn/requirements.txt. Takes ~2 min.
set -e
cd "$(dirname "$0")"
mkdir -p run
python3 ../snn/sim_vectors.py "$1" --window "${2:-0}" --weights ../snn/weights_live.npz --out run
cp ../syn/snn_rom.hex run/
R=../../rtl     # your design
S=../rtl        # scaffold
iverilog -g2012 -o run/top.vvp \
  $R/common/snn_pkg.sv $R/acc/mem/config_mem.sv $R/acc/mem/conn_mem.sv $R/acc/mem/meta_mem.sv \
  $R/acc/engine/syn_eng.sv $R/acc/engine/lif_eng.sv $R/acc/engine/snn.sv \
  $R/acc/peripheral/dencode.sv $R/acc/peripheral/spike_record.sv $R/acc/peripheral/spi.sv \
  $R/acc/peripheral/seq.sv $R/acc/peripheral/byte_assmbl.sv $R/acc/peripheral/master.sv \
  $S/snn_loader.sv $S/readout.sv $S/class_display.sv $S/de10_top.sv \
  adxl345_model.sv de10_top_tb.sv
cd run && vvp top.vvp | grep -v readmemh
