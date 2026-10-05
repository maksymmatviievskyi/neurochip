"""
Accelerometer data: synthetic gesture generator, recording loader, and the delta (level-crossing) encoder.

Raw data format (synthetic or recorded) -- keep RAW samples, never only spikes, so you can re-encode:
    raw     : int16 array (N, T, 3)   ADXL345 counts for x, y, z (full-res: ~3.9 mg/LSB, 1 g ~ 256)
    labels  : int   array (N,)
    session : int   array (N,)        recording session id (validate on whole sessions)
Saved as .npz with exactly those keys.

The encoder below defines the spike semantics. The RTL encoder must implement the SAME rules.
"""
import numpy as np

FS = 400                      # sample rate [Hz] -> one SNN timestep per sample (2.5 ms)
T = 256                       # window length in timesteps (640 ms)
STEPS = (10, 25, 60, 150, 400, 1000)   # from recordings: idle noise ~2 LSB; hard taps/shakes reach ~1000+ LSB per sample

# Live trigger (identical in hw/rtl/live/snn_live.sv): a one-step delta encoder with TRIG_STEP runs on the
# raw stream; the first spike on any axis at sample i (with i >= next_allowed) starts a window at i - PRE.
TRIG_STEP = 25
PRE = 100
CLASSES = ("idle", "light_tap", "hard_tap", "double_tap", "shake")
N_AXES = 3
N_IN = N_AXES * len(STEPS) * 2    # 36


def channel(axis, level, down):
    """Input-neuron index for (axis 0..2, step level 0..L-1, down 0=UP / 1=DOWN)."""
    return axis * 2 * len(STEPS) + level * 2 + down


# ----------------------------------------------------------------------------------------------
# Delta encoder
# ----------------------------------------------------------------------------------------------
def encode(raw, steps=STEPS):
    """
    raw: (N, T, 3) int  ->  spikes: (N, T, 3*2*L) uint8

    Per channel (axis a, step s) keep a reference value `ref` (initialised to the first sample).
    Each timestep, at most ONE spike per neuron:
        d = x - ref
        d >=  s : UP spike,   ref += s
        d <= -s : DOWN spike, ref -= s
    """
    raw = np.asarray(raw, dtype=np.int64)
    N, Tn, A = raw.shape
    L = len(steps)
    s = np.asarray(steps, dtype=np.int64)[None, None, :]          # (1,1,L)
    ref = np.repeat(raw[:, 0, :, None], L, axis=2)                  # (N,A,L)
    out = np.zeros((N, Tn, A, L, 2), dtype=np.uint8)
    for t in range(Tn):
        d = raw[:, t, :, None] - ref
        up = d >= s
        dn = d <= -s
        ref = ref + s * up - s * dn
        out[:, t, :, :, 0] = up
        out[:, t, :, :, 1] = dn
    return out.reshape(N, Tn, A * L * 2)


# ----------------------------------------------------------------------------------------------
# Synthetic gestures (pipeline development only -- accuracy on these means little)
# ----------------------------------------------------------------------------------------------
def _tap(T_, onset, amp, rng):
    """Damped oscillation on z: what a tap looks like on an accelerometer."""
    t = np.arange(T_) - onset
    f = rng.uniform(40, 80)                   # ringing frequency [Hz]
    tau = rng.uniform(0.008, 0.02) * FS       # decay [samples]
    sig = amp * np.exp(-np.clip(t, 0, None) / tau) * np.cos(2 * np.pi * f * t / FS)
    sig[t < 0] = 0
    return sig


def _gesture(label, rng):
    x = np.zeros((T, 3))
    if label == 0:                                   # idle: occasional tiny bump
        if rng.random() < 0.3:
            x[:, rng.integers(3)] += _tap(T, rng.integers(T), rng.uniform(3, 10), rng)
    elif label in (1, 2):                            # single tap, light or hard
        amp = rng.uniform(20, 60) if label == 1 else rng.uniform(120, 300)
        onset = rng.integers(20, T - 60)
        x[:, 2] += _tap(T, onset, amp * rng.choice([-1, 1]), rng)
        x[:, rng.integers(2)] += _tap(T, onset, 0.15 * amp, rng)      # cross-axis coupling
    elif label == 3:                                 # double tap, 100-300 ms apart
        gap = rng.integers(int(0.10 * FS), int(0.30 * FS))
        onset = rng.integers(10, T - gap - 40)
        sgn = rng.choice([-1, 1])
        for o in (onset, onset + gap):
            x[:, 2] += _tap(T, o, sgn * rng.uniform(40, 250), rng)
    elif label == 4:                                 # shake: 3-7 Hz along x, ~0.4-0.6 s
        f = rng.uniform(3, 7)
        dur = int(rng.uniform(0.4, 0.6) * FS)
        onset = rng.integers(0, T - dur)
        tt = np.arange(dur)
        env = np.sin(np.pi * tt / dur)
        amp = rng.uniform(100, 300)
        burst = amp * env * np.sin(2 * np.pi * f * tt / FS + rng.uniform(0, 2 * np.pi))
        x[onset:onset + dur, 0] += burst
        x[onset:onset + dur, 1] += 0.2 * burst * rng.uniform(-1, 1)
    return x


def make_synthetic(n_per_class, seed, noise_lsb=1.5):
    rng = np.random.default_rng(seed)
    raws, labels = [], []
    for label in range(len(CLASSES)):
        for _ in range(n_per_class):
            x = _gesture(label, rng)
            x[:, 2] += 256                                          # gravity on z
            drift = np.cumsum(rng.normal(0, 0.05, (T, 3)), axis=0)  # slow hand drift
            x += drift + rng.normal(0, noise_lsb, (T, 3))
            raws.append(np.round(x))
            labels.append(label)
    raw = np.clip(np.stack(raws), -512, 511).astype(np.int16)      # 10-bit-ish range at +-2 g
    labels = np.array(labels)
    return raw, labels, np.full(len(labels), seed)


def hw_windows(raw):
    """
    Window start indices the board's trigger produces for one continuous recording raw: (n, 3).
    Mirrors snn_live.sv: trigger encoder initialised on sample 0; a trigger at sample i (i >= PRE and
    i >= next_allowed) gives a window [i - PRE, i - PRE + T); the next trigger is accepted from the
    end of that window. Windows that would run past the end of the recording are dropped.
    """
    trig = encode(raw[None], steps=(TRIG_STEP,))[0].any(axis=1)
    starts, next_allowed = [], 0
    for i in np.flatnonzero(trig):
        if i < PRE or i < next_allowed:
            continue
        s = i - PRE
        if s + T > len(raw):
            break
        starts.append(int(s))
        next_allowed = s + T
    return starts


def load_recordings(path):
    d = np.load(path)
    return d["raw"].astype(np.int16), d["labels"].astype(int), d["session"].astype(int)
