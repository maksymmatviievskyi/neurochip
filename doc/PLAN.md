# Project plan & progress

**Goal:** an event-driven spiking neural network accelerator on the DE10-Lite (MAX 10 10M50DAF484C7G)
that classifies gestures from the onboard ADXL345 accelerometer in real time, with work that scales
with input activity. Driven by a small RV32I core. Portfolio piece for Arm / hardware roles and
neuromorphic research groups.

**Why this task:** SNNs only win on sparse, time-varying input. A board lying still produces zero
spikes, so an event-driven accelerator should do (almost) zero work; a conventional network
recomputes every sample. The demo has to *measure* that, not just claim it.

Status legend: `[x]` done · `[~]` in progress · `[ ]` to do · `[-]` dropped

---

## Phase 0 — SNN accelerator core  ✅

- [x] Synaptic engine (`syn_eng`): event-driven, one source spike at a time, CSR-style connection memory
- [x] LIF engine (`lif_eng`): serial, pipelined (1 neuron/cycle, zero bubbles), membrane V in M9K, CLEAR sweep after reset
- [x] `snn` controller: layer sequencing, `init` gated on `lif_cleared`
- [x] `snn_tb`: 13 timesteps over 2 networks, bit-exact vs reference model (spikes **and** membrane V)
- [x] Quartus compile, core only (virtual pins): fits
- [ ] Fmax / setup slack @ 50 MHz recorded (Slow 1200mV 85C)
- [x] Device set to `10M50DAF484C7G` (was I7G); Quartus project in `hw/syn/`
- [x] `.gitignore` for Quartus output; commit `.qpf/.qsf/.sdc`
- [x] Widen `THRESHOLD_W` (and reset value) to 16 bits **before exporting trained weights**
- [x] Delete stale `tb/acc/lif_tb.sv` (instantiates non-existent `lif`)

## Phase 1 — Sensor front end & spike encoding

- [ ] ADXL345 SPI master (3-wire/4-wire per board wiring; check DE10-Lite manual), read X/Y/Z at a fixed rate (e.g. 400 Hz)
- [ ] Delta / level-crossing encoder, same rules as `snn/data.py::encode` (3 axes × UP/DOWN × 6 step sizes = 36 inputs)
- [ ] Live spike display on LEDR (demo #1: still board = dark LEDs)
- [ ] Testbench with recorded/synthetic accelerometer traces

**Gate:** live spikes visible on the LEDs before moving on.

## Phase 2 — Data collection

- [ ] Recorder design (`hw/syn/recorder/`): 16384 × 48-bit RAM with In-System Memory Content Editor (instance `REC`), 16 windows × 1024 samples, KEY0 clear / KEY1 record
- [ ] Bring-up: read ADXL345 DEVID (0x00) = `E5` on HEX
- [ ] Record ≥ 3 sessions × 5 classes × 16 windows; dump as `s<session>_<class>.mif`; `snn/import_recordings.py` → `recordings.npz`
- [x] Classes: idle, light tap, hard tap, double tap, shake
- [ ] Optional: 3.3 V USB-UART adapter for live streaming to the Mac

## Phase 3 — Training (Python)

- [~] Bit-exact integer LIF model (`snn/snn_int.py`) — still to cross-check against `snn_tb` networks A/B
- [x] Surrogate-gradient training (`snn/train.py`, PyTorch, 36 → 64 → 5), quantise to int16, integer-model check — synthetic data: 98 % float / 98 % integer
- [ ] Exporter: `weights.hex` (config, layer ranges, neuron meta, connections) + `expected.txt` for test set
- [ ] Cross-check: Python integer model vs `snn_tb` on exported network

## Phase 4 — On-board classification

- [ ] Loader FSM: ROM (`$readmemh`) → `snn` write ports after reset
- [ ] Timestep controller: encoder spikes → `spikesIn`, `init`, collect output spikes, decision (spike count / first-to-fire)
- [ ] HEX display of class; LEDs for output spikes
- [ ] Top-level testbench on recorded traces vs `expected.txt`
- [ ] `syn/de10_top/` project, pin assignments from Terasic DE10-Lite System CD, KEY0 reset synchroniser
- [ ] Demo video

## Phase 5 — Measure the event-driven advantage

- [ ] Hardware counters: synaptic ops, LIF updates, busy cycles — per second, idle vs active
- [ ] Comparison: MACs of an equivalent dense ANN evaluated every sample
- [ ] Event-driven LIF: skip the sweep when a timestep has no input spikes and no neuron near threshold (or lazy leak); re-measure idle cost
- [ ] Gesture-to-decision latency

## Phase 6 — CPU integration

- [ ] RV32I core: immediates, load/store, branches/jumps, PC logic (decoder already uses RV32I encodings)
- [ ] Memory-mapped SNN registers (APB-style), C firmware via RISC-V GCC
- [ ] Firmware loads weights (replaces loader FSM) and runs on-board self-test vs stored expected outputs → PASS/FAIL on HEX

## Phase 7 — Presentation

- [ ] README: block diagram, design decisions, verification approach, results table
- [ ] CI (GitHub Actions): lint + `snn_tb` on every push
- [ ] Short write-up for professors (design trade-offs + idle/active measurements)

---

## Results so far

| Metric | Value | Notes |
|---|---|---|
| LIF, parallel (original) | ~64k LUT4 est. → **does not fit** (~130 %) | Yosys estimate |
| SNN core, serial LIF (Quartus) | **6,713 LE (13 %)**, 3,643 regs, 100,992 memory bits | 2 Oct 2026, core only, virtual pins |
| Cycles / timestep, test network A | 40 (parallel) → 80 → 66 → 63 → **60** | serialise, then pipeline, then remove bubbles |
| Fmax @ Slow 85C | _tbd_ | target ≥ 50 MHz |
| Classification accuracy | 98 % (synthetic only) | 36→64→5, k=6, scale 8192; real data tbd |
| Synaptic ops/s idle vs active | _tbd_ | synthetic: ~10k ops/window vs 672k MACs dense ANN (~66×) |

## Hardware

| Item | Status |
|---|---|
| DE10-Lite (ADXL345 onboard) | have |
| 3.3 V USB-UART adapter (FT232/CP2102) | **ask EEE stores** |
| Later options: AD8232 ECG, AMG8833 8×8 thermal, 2× electret mic (MAX9814) | not yet |

## Decisions

- **2 Oct** — Application: event-driven accelerometer gestures (not static images: SNNs have no advantage there).
- **2 Oct** — LIF serialised + pipelined; V in M9K. Area/latency trade documented above.
- **1 Oct** — Keep RV32I encodings for the core (GCC toolchain), not a custom ISA.
- **24 Sep** — Synaptic engine processes one spike at a time (M9K has ≤ 2 ports).

## Progress log

- **4 Oct** — Repository reorganised: hardware under `hw/` (rtl, tb, syn), model and training under `snn/`, docs under `doc/`.

- **4 Oct** — Training pipeline in `snn/`: delta encoder (36 inputs, steps 6–192), synthetic gestures (5 classes), surrogate-gradient BPTT, int16 quantisation; synthetic val 98 % float and integer.

- **2 Oct** — Serial pipelined LIF passes `snn_tb` bit-exact (60 cycles/timestep on net A). First Quartus compile: 13 % LE. Plan switched to accelerometer gestures.
- **1 Oct** — Found parallel LIF needs ~130 % of the FPGA; started serial version.
