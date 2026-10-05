# SNN model & training

Software side of the accelerator: the network, the input spike encoder, surrogate-gradient training,
integer quantisation, and an integer reference model that follows the RTL (`hw/rtl/acc`) bit for bit.

| File | Purpose |
|---|---|
| `snn.py` | LIF network definition and leak-aware weight initialisation |
| `train.py` | Surrogate-gradient BPTT training, firing-rate calibration, int16 quantisation, integer-model check |
| `snn_int.py` | Integer reference model: `V ← V − (V >>> k) + I`, spike if `V ≥ θ`, reset to `V_reset`; range-checks against the hardware widths (I: 23 bit, V: 25 bit) |
| `data.py` | Delta (level-crossing) encoder, synthetic gestures, recording loader |
| `import_recordings.py` | Converts recorder RAM dumps (`.mif`, In-System Memory Content Editor) into `recordings.npz` |

## Hyperparameter choices

- **Inputs (36):** the ADXL345 gives 3 axes; each needs two neurons (UP / DOWN) because spikes are binary.
  Tap strength is encoded with 6 step sizes, so 3 × 2 × 6 = 36 input neurons.
- **Decay shift k = 6:** leak factor 1 − 2⁻⁶, membrane time constant ≈ 64 timesteps ≈ 160 ms at 400 Hz —
  long enough to bridge the gap of a double tap.
- **Network:** 36 → 64 → 5 (105 neurons, 2,624 connections; hardware limit 128 / 4,096).

## Usage

```bash
pip install -r requirements.txt
python train.py                                   # synthetic gestures (pipeline check)
python import_recordings.py recordings/*.mif      # board recordings -> recordings.npz
python train.py --data recordings.npz             # validates on the last recording session
```

`train.py` writes `weights_int.npz` (integer weights, threshold, reset, k, scale, encoder steps).


idle, light_tap, hard_tap, double_tap, shake are the classes