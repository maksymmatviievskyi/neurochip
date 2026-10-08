# scaffold/ — temporary board harness (written by Claude, not part of the main design)

Everything in this folder is helper code so the design in `rtl/` can run live on the DE10-Lite
before the remaining blocks are written by hand. It only *uses* files from `rtl/`; nothing in `rtl/`
depends on it. It lives on the `scaffold` branch only — `main` never contains it.

| Path | What |
|---|---|
| `rtl/snn_loader.sv` | copies the trained network from a ROM (`$readmemh`) into the snn memories after reset |
| `rtl/readout.sv` | output spikes over the last 256 timesteps, decision every 32, gesture = peak of a non-idle run |
| `rtl/class_display.sv` | class names on HEX5..HEX0 (IdLE, L-tAP, H-tAP, d-tAP, SHAKE) |
| `rtl/de10_top.sv` | board top: master -> spike_record -> snn -> readout -> HEX, LEDs, reset |
| `syn/` | Quartus project `de10.qpf` (pins, timing, `snn_rom.hex` = trained weights) |
| `tb/` | fake ADXL345 + system testbench, bit-exact against the Python model (`sh run.sh ...`) |
| `snn/` | training (`train_live.py`), test vectors, CNN baseline, recordings |

## Compile (Windows / Quartus)
    git switch scaffold
    open scaffold/syn/de10.qpf -> Compile -> Programmer -> output_files/de10.sof

## Keep it up to date with your work on main
    git switch scaffold
    git merge main          # never conflicts: scaffold only adds this folder

## Remove it for good
    git switch main
    git branch -D scaffold
    git push origin --delete scaffold
