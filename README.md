# neurochip

An event-driven spiking neural network (SNN) accelerator in SystemVerilog for the Terasic DE10-Lite
(Intel MAX 10, 10M50), with a small RV32I core in progress. The target application is real-time gesture
recognition from the board's ADXL345 accelerometer, where an event-driven network does almost no work
while the board is still.

## Repository layout

```
hw/                 hardware
  rtl/acc/engine    snn controller, synaptic engine (event-driven), LIF engine (serial, pipelined)
  rtl/acc/mem       configuration, layer/neuron metadata and connectivity memories (M9K)
  rtl/core          RV32I core (in progress)
  rtl/common        packages
  tb/               testbenches (Icarus Verilog, -g2012)
  syn/              Quartus project (core-only build, virtual pins)
snn/                model, encoder, surrogate-gradient training, integer reference model
doc/                architecture notes, ideation log, plan & progress
```

## Accelerator

- **Synaptic engine** processes one source spike at a time, so synaptic work scales with input activity.
- **LIF engine** updates one neuron per cycle with membrane potentials in block RAM:
  `V ← V − (V >>> k) + I`, spike when `V ≥ θ`, then `V ← V_reset`.
- Limits: 128 neurons, 4,096 connections, 16 layers, 16-bit weights and thresholds.

| Result | Value |
|---|---|
| Fully parallel LIF engine (first version) | ~130 % of the FPGA's logic (does not fit) |
| Serial pipelined LIF, whole SNN core (Quartus) | 6,713 LEs (13 %), 100,992 memory bits |
| `snn_tb` | bit-exact against a reference model (spikes and membrane potentials) |
| Training (synthetic gestures, 36 → 64 → 5) | 98 % float, 98 % after int16 quantisation |

See [`doc/PLAN.md`](doc/PLAN.md) for the roadmap and progress log.

## Running

```bash
# hardware testbench
cd hw && iverilog -g2012 -o snn_tb.vvp rtl/common/snn_pkg.sv rtl/acc/mem/config_mem.sv \
  rtl/acc/mem/conn_mem.sv rtl/acc/mem/meta_mem.sv rtl/acc/engine/*.sv tb/acc/snn_tb.sv && vvp snn_tb.vvp

# model
cd snn && pip install -r requirements.txt && python train.py
```
