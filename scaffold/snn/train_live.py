"""
Train the gesture SNN for CONTINUOUS (live) operation on the DE10-Lite, and export the board ROM.

Hardware it must match (rtl/acc/peripheral + rtl/top):
  * dencode   : delta encoder, initialised once on the first sample after reset, then runs on every sample
  * snn       : one timestep per sample (400 Hz); membrane potentials are NEVER reset between gestures
  * readout   : output spikes summed over the last W timesteps; every D timesteps class = argmax
                (ties -> lowest index = idle)

So training uses windows of P (pre-roll) + T timesteps cut from the continuous recording:
  * the encoder runs over the whole 1024-sample recording (warm, like the board)
  * the network starts from zero P steps before the T-step window (state is warm when the window starts)
  * the loss uses output spike counts over the last T steps only (= what the readout sums)
Crops with the gesture fully inside T get the gesture label; crops where the gesture lies completely
outside the P+T span get "idle", so the network learns to stay quiet between gestures.

    python train_live.py recordings/*.mif                     # validate on the last session
    python train_live.py recordings/*.mif --all --rom ../syn/snn_rom.hex   # final model + ROM
"""
import argparse
import os
import re
import numpy as np
import torch
import torch.nn.functional as F

import data
import import_recordings as ir
from snn_int import quantize, run_int
from train import TrainSNN, calibrate

STEPS = (8, 32, 128, 256, 512, 1024)      # must equal dencode.sv STEPS
NETSHAPE = (36, 64, 5)
P, T = 128, 256                           # pre-roll, window (= readout W)
W, D = 256, 32                            # readout window and decision period [timesteps]
MAX_NEURONS, MAX_CONN = 128, 4096


# ------------------------------------------------------------------------------------------------
def load_windows(paths):
    """-> list of (session, label, raw (1024, 3) int, gesture_first, gesture_last)"""
    out = []
    for path in sorted(paths):
        m = re.match(r"s(\d+)_(.+)\.mif$", os.path.basename(path), re.I)
        hits = [c for c in data.CLASSES if m and (m.group(2) == c or m.group(2).startswith(c + "_"))]
        if not hits:
            print(f"skip {path}")
            continue
        sess, label = int(m.group(1)), data.CLASSES.index(max(hits, key=len))
        xyz = ir.unpack(ir.read_mif(path))
        for w in range(ir.WORDS // ir.WIN):
            win = xyz[w * ir.WIN:(w + 1) * ir.WIN]
            if not win.any():
                continue
            f = l = None
            if label != 0:
                wf = win.astype(float)
                base = np.stack([np.convolve(wf[:, a], np.ones(65) / 65, mode="same") for a in range(3)], 1)
                act = np.convolve(np.abs(wf - base).sum(1), np.ones(8) / 8, mode="same")[32:-32]
                idx = np.flatnonzero(act > max(np.median(act) * 4, 4.0)) + 32
                if len(idx) == 0:
                    continue                                 # gesture missed while recording
                f, l = int(idx[0]), int(idx[-1])
            out.append((sess, label, win, f, l))
    return out


def make_crops(wins, rng, n_pos=10, n_neg=4):
    """Cut (P+T)-step crops out of the warm-encoded recordings. -> x (N, P+T, 36), y (N,)"""
    X, Y = [], []
    L = P + T
    for sess, label, win, f, l in wins:
        spk = data.encode(win[None], steps=STEPS)[0]         # encoder warm over the whole recording
        n = len(win)
        if label == 0:
            for s in rng.integers(0, n - L, n_pos + n_neg):
                X.append(spk[s:s + L]); Y.append(0)
            continue
        # gesture inside the T window (leave >= 8 steps margin); long gestures may be clipped at the edges
        lo = max(0, l + 8 - L)
        hi = min(n - L, f - 8 - P)
        if hi < lo:                                          # longer than T: centre it
            lo = hi = int(np.clip((f + l) // 2 - P - T // 2, 0, n - L))
        for s in rng.integers(lo, hi + 1, n_pos):
            X.append(spk[s:s + L]); Y.append(label)
        # negatives: the whole P+T span before or after the gesture
        cands = list(range(0, max(0, f - 16 - L))) + list(range(l + 16, n - L))
        if cands:
            for s in rng.choice(cands, min(n_neg, len(cands)), replace=False):
                X.append(spk[s:s + L]); Y.append(0)
    return np.stack(X).astype(np.float32), np.array(Y)


class LiveSNN(TrainSNN):
    def forward(self, x):                                    # counts over the last T steps only
        B, Tn, _ = x.shape
        v = [x.new_zeros(B, n) for n in self.layers[1:]]
        counts = [x.new_zeros(B, n) for n in self.layers[1:]]
        for t in range(Tn):
            cur = x[:, t]
            for i, w in enumerate(self.W):
                cur, v[i] = self.lif(cur, v[i], w)
                if t >= Tn - T:
                    counts[i] = counts[i] + cur
        return counts


# ------------------------------------------------------------------------------------------------
def stream_decisions_full(raw, Wq, thr, rst, k):
    """Bit-exact board behaviour on one continuous recording (dencode + snn + readout.sv):
    list of (t, class, winning count) for every decision, t = timestep index from the first sample."""
    spk = data.encode(raw[None], steps=STEPS)[0]
    x = spk.astype(np.int64)
    V = [np.zeros(w.shape[0], np.int64) for w in Wq]
    hist = np.zeros((len(raw), Wq[-1].shape[0]), np.int64)
    dec = []
    for t in range(len(raw)):
        cur = x[t]
        for i, w in enumerate(Wq):
            vn = V[i] - (V[i] >> k) + w @ cur
            s = vn >= thr
            V[i] = np.where(s, rst, vn)
            cur = s.astype(np.int64)
        hist[t] = cur
        if (t + 1) % D == 0:
            c = hist[max(0, t + 1 - W):t + 1].sum(0)
            dec.append((t, int(np.argmax(c)), int(c.max())))   # argmax: ties -> lowest index (idle)
    return dec


def gesture_results(dec):
    """readout.sv events: each run of non-idle decisions -> class of its highest winning count."""
    events, cur = [], None
    for t, c, top in dec:
        if c != 0:
            if cur is None or top > cur[1]:
                cur = (c, top)
        elif cur is not None:
            events.append(cur[0]); cur = None
    if cur is not None:
        events.append(cur[0])
    return events


def evaluate_stream(wins, Wq, thr, rst, k, verbose=True):
    """Per recording: the peak class over the gesture events after the first full window (idle if none)."""
    nC = len(data.CLASSES)
    cm = np.zeros((nC, nC), int)
    for sess, label, win, f, l in wins:
        d = [x for x in stream_decisions_full(win, Wq, thr, rst, k) if x[0] >= W]
        nz = [x for x in d if x[1] != 0]
        pred = max(nz, key=lambda x: x[2])[1] if nz else 0
        cm[label, pred] += 1
    acc = np.trace(cm) / cm.sum()
    if verbose:
        print("live (continuous) confusion, rows = true, cols = predicted:", ", ".join(data.CLASSES))
        print(cm)
        print(f"live accuracy {acc:.3f}")
    return acc, cm


# ------------------------------------------------------------------------------------------------
def write_rom(path, Wq, thr, rst, k):
    """Board ROM for snn_loader.sv: word 0 = {n_cmd[15:0], 48'b0}; word i = {type[1:0], addr[13:0], payload[47:0]}
    type 0 config  : payload {threshold[15:0], decay[3:0], reset[15:0], num_layers[11:0]} at [47:32],[31:28],[27:12],[11:0]
    type 1 layer   : payload {start[39:8], count[7:0]}
    type 2 neuron  : payload {start[24:13], count[12:0]}
    type 3 conn    : payload {src[29:23], dst[22:16], w[15:0]}"""
    shape = [Wq[0].shape[1]] + [w.shape[0] for w in Wq]
    starts = np.cumsum([0] + shape[:-1])
    conns = []
    for l, Wl in enumerate(Wq):
        for i in range(Wl.shape[1]):
            for j in range(Wl.shape[0]):
                if Wl[j, i] != 0:
                    conns.append((int(starts[l] + i), int(starts[l + 1] + j), int(Wl[j, i])))
    conns.sort(key=lambda c: c[0])
    assert len(conns) <= MAX_CONN and sum(shape) <= MAX_NEURONS
    nstart = np.zeros(MAX_NEURONS, int); ncount = np.zeros(MAX_NEURONS, int)
    for idx, (s, _, _) in enumerate(conns):
        if ncount[s] == 0:
            nstart[s] = idx
        ncount[s] += 1
    cmds = []
    for l in range(len(shape)):
        cmds.append((0, l, ((thr & 0xFFFF) << 32) | ((k & 0xF) << 28) | ((rst & 0xFFFF) << 12) | len(shape)))
    for l in range(len(shape)):
        cmds.append((1, l, (int(starts[l]) << 8) | shape[l]))
    for n in range(MAX_NEURONS):
        cmds.append((2, n, (int(nstart[n]) << 13) | int(ncount[n])))
    for c, (s, d, w) in enumerate(conns):
        cmds.append((3, c, (s << 23) | (d << 16) | (w & 0xFFFF)))
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w") as f:
        f.write(f"{len(cmds) << 48:016x}\n")
        for t_, a_, p_ in cmds:
            f.write(f"{(t_ << 62) | (a_ << 48) | p_:016x}\n")
    print(f"ROM: {len(cmds)} write commands ({len(conns)} connections, {sum(shape)} neurons, "
          f"output neurons {starts[-1]}..{starts[-1] + shape[-1] - 1}) -> {path}")


# ------------------------------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    ap.add_argument("--val-session", type=int, default=None)
    ap.add_argument("--all", action="store_true", help="train on every session (final model)")
    ap.add_argument("--k", type=int, default=6)
    ap.add_argument("--epochs", type=int, default=40)
    ap.add_argument("--lr", type=float, default=3e-3)
    ap.add_argument("--batch", type=int, default=32)
    ap.add_argument("--lam", type=float, default=1e-3)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--rom", default=None)
    ap.add_argument("--out", default="weights_live.npz")
    args = ap.parse_args()
    torch.manual_seed(args.seed); rng = np.random.default_rng(args.seed)
    torch.set_num_threads(os.cpu_count() or 1)

    wins = load_windows(args.files)
    sess = np.array([w[0] for w in wins])
    vs = args.val_session if args.val_session is not None else sess.max()
    tr = [w for w in wins if args.all or w[0] != vs]
    va = [w for w in wins if w[0] == vs] if not args.all else wins
    print(f"recordings: train {len(tr)}  validate {len(va)} (session {'all' if args.all else vs})")

    x_tr, y_tr = make_crops(tr, rng)
    x_va, y_va = make_crops(va, np.random.default_rng(123))
    print(f"crops: train {len(y_tr)} {np.bincount(y_tr, minlength=5)}  val {len(y_va)}  "
          f"input spike prob {x_tr.mean():.4f}")
    Xtr, Ytr, Xva = torch.from_numpy(x_tr), torch.from_numpy(y_tr).long(), torch.from_numpy(x_va)

    model = LiveSNN(args.k, 1.0, 0.0, list(NETSHAPE), 5.0)
    model.init_weights(fire_rate=max(float(x_tr.mean()), 1e-3), std_gain=1.0, mean_gain=0.0)
    calibrate(model, Xtr[torch.randperm(len(Xtr))[:128]], targets=[0.03, 0.01])
    opt = torch.optim.Adam(model.parameters(), lr=args.lr)
    for ep in range(args.epochs):
        perm = torch.randperm(len(Xtr)); tot = 0.0
        for b in range(0, len(perm), args.batch):
            idx = perm[b:b + args.batch]
            counts = model(Xtr[idx])
            loss = F.cross_entropy(counts[-1], Ytr[idx]) + args.lam * sum(c.mean() for c in counts[:-1])
            opt.zero_grad(); loss.backward(); opt.step()
            tot += loss.item() * len(idx)
        if ep % 5 == 4 or ep == args.epochs - 1:
            with torch.no_grad():
                cv = model(Xva)
            acc = float((cv[-1].argmax(1).numpy() == y_va).mean())
            print(f"epoch {ep:3d}  loss {tot / len(Xtr):.4f}  crop val acc {acc:.3f}  "
                  f"hidden rate {cv[0].mean().item() / T:.4f}")

    Wq, thr, rst, scale = quantize([w.detach().numpy() for w in model.W], 1.0, 0.0, args.k)
    ci, imax, vmax = run_int(x_va.astype(np.uint8), Wq, thr, rst, args.k)   # P+T counts, sanity only
    print(f"threshold_int {thr}  reset_int {rst}  k {args.k}  max|I| {imax}  max|V| {vmax}")
    evaluate_stream(va, Wq, thr, rst, args.k)
    np.savez(args.out, **{f"W{i}": w for i, w in enumerate(Wq)}, threshold=thr, reset=rst, k=args.k,
             steps=np.array(STEPS), netshape=np.array(NETSHAPE), W=W, D=D)
    print(f"saved {args.out}")
    if args.rom:
        write_rom(args.rom, Wq, thr, rst, args.k)


if __name__ == "__main__":
    main()
