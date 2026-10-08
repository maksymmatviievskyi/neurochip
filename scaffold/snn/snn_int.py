"""
Integer reference model -- bit-exact with the RTL (lif_eng / syn_eng / snn).

Per timestep, layers in order, no synaptic delay:
    I      = sum of weights from source neurons that spiked this timestep    (syn_eng, I_W = 23 bits)
    V_next = V - (V >>> k) + I                                               (arithmetic shift)
    spike  = V_next >= threshold   (signed)
    V      = reset_value if spike else V_next                                 (V is 25 bits)
V persists across timesteps until reset (call with fresh state per sample = hardware soft-clear).
"""
import numpy as np

WEIGHT_W = 16
THRESHOLD_W = 16
I_W = WEIGHT_W + 7          # WEIGHT_W + NEURON_ADDR_W
V_BITS = I_W + 2            # logic signed [V_W:0], V_W = I_W + 1


def _fits(x, bits):
    lim = 1 << (bits - 1)
    return x.min() >= -lim and x.max() < lim


def quantize(Ws_float, threshold, reset_v, k, scale=None):
    """
    Map float weights (threshold `threshold`) to integers.
    Scale S: as large as possible (precision) while every weight and the threshold fit in 16 bits.
    Leak dead-zone: V >> k == 0 for 0 <= V < 2^k, so we want threshold_int >= 16 * 2^k.
    """
    wmax = max(float(np.abs(w).max()) for w in Ws_float)
    lim = (1 << (WEIGHT_W - 1)) - 1
    if scale is None:
        scale = min(lim / wmax, lim / max(abs(threshold), abs(reset_v), 1e-9))
        scale = float(2 ** np.floor(np.log2(scale)))      # power of two: easy to reason about
    Wq = [np.round(w * scale).astype(np.int64) for w in Ws_float]
    thr = int(round(threshold * scale))
    rst = int(round(reset_v * scale))
    for w in Wq:
        assert _fits(w, WEIGHT_W), "weight overflow"
    assert _fits(np.array([thr, rst]), THRESHOLD_W), "threshold/reset overflow"
    if thr < 16 * 2 ** k:
        print(f"warning: threshold_int={thr} < 16*2^k={16 * 2 ** k}: leak dead-zone will be noticeable")
    return Wq, thr, rst, scale


def run_int(spikes_in, Wq, thr, rst, k):
    """
    spikes_in: (N, T, n_in) {0,1};  Wq: list of int arrays (n_out, n_in) per layer.
    Returns spike counts per layer [(N, n_l)] and the max |I|, |V| seen (for headroom reporting).
    """
    x = np.asarray(spikes_in, dtype=np.int64)
    N, T, _ = x.shape
    V = [np.zeros((N, w.shape[0]), dtype=np.int64) for w in Wq]
    counts = [np.zeros((N, w.shape[0]), dtype=np.int64) for w in Wq]
    imax = vmax = 0
    for t in range(T):
        cur = x[:, t]
        for i, w in enumerate(Wq):
            I = cur @ w.T
            assert _fits(I, I_W), f"I overflow at t={t}, layer {i}"
            vn = V[i] - (V[i] >> k) + I                  # numpy >> on int64 is arithmetic (floor)
            assert _fits(vn, V_BITS), f"V overflow at t={t}, layer {i}"
            spk = vn >= thr
            V[i] = np.where(spk, rst, vn)
            counts[i] += spk
            imax = max(imax, int(np.abs(I).max()))
            vmax = max(vmax, int(np.abs(vn).max()))
            cur = spk.astype(np.int64)
    return counts, imax, vmax
