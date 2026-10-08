"""
Surrogate-gradient training for the network in snn.py, then integer quantisation + bit-exact check.

    python train.py                         # synthetic data (pipeline check)
    python train.py --data recordings.npz   # your recordings (raw, labels, session); validates on --val-session

Outputs: weights_int.npz (integer weights, threshold, reset, k, scale, encoder steps) and a printed report.
"""
import argparse
import numpy as np
import torch
import torch.nn.functional as F

from snn import snn, netshape
import data
from snn_int import quantize, run_int


# ----------------------------------------------------------------------------------------------
# Surrogate spike: forward = step function, backward = fast-sigmoid derivative
# ----------------------------------------------------------------------------------------------
class SpikeFn(torch.autograd.Function):
    @staticmethod
    def forward(ctx, x, slope):          # x = v - threshold
        ctx.save_for_backward(x)
        ctx.slope = slope
        return (x >= 0).to(x.dtype)

    @staticmethod
    def backward(ctx, grad):
        (x,) = ctx.saved_tensors
        return grad / (1.0 + ctx.slope * x.abs()) ** 2, None


class TrainSNN(snn):
    """Your snn, with: batching, state carried across timesteps, surrogate gradient, reset to resetV."""

    def __init__(self, decayShift, threshold, resetV, layers, slope):
        super().__init__(decayShift, threshold, resetV, layers)
        self.slope = slope

    def lif(self, s, v, w):                                  # s: (B, n_in), v: (B, n_out)
        v = v - v / 2 ** self.decayShift + s @ w.T
        spikes = SpikeFn.apply(v - self.threshold, self.slope)
        r = spikes.detach()                                  # no gradient through the reset
        v = v * (1 - r) + self.resetV * r
        return spikes, v

    def forward(self, x):                                    # x: (B, T, n_in) -> spike counts per layer
        B, T, _ = x.shape
        v = [x.new_zeros(B, n) for n in self.layers[1:]]
        counts = [x.new_zeros(B, n) for n in self.layers[1:]]
        for t in range(T):
            cur = x[:, t]
            for i, w in enumerate(self.W):
                cur, v[i] = self.lif(cur, v[i], w)
                counts[i] = counts[i] + cur
        return counts


@torch.no_grad()
def calibrate(model, x, targets, iters=12):
    """Rescale each layer (first to last) so its mean firing rate per timestep ~ target."""
    T = x.shape[1]
    for i, target in enumerate(targets):
        for _ in range(iters):
            rate = model(x)[i].mean().item() / T
            if rate == 0:
                model.W[i].mul_(2.0)
                continue
            if abs(rate / target - 1) < 0.15:
                break
            model.W[i].mul_(float(np.clip((target / rate) ** 0.5, 0.5, 2.0)))
        print(f"  calibrate layer {i}: rate {rate:.4f} (target {target})")


def accuracy(counts_out, y):
    # ties (e.g. all zero) -> lowest index; class 0 is "idle", the safe default
    return float((np.argmax(counts_out, axis=1) == y).mean())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", default=None)
    ap.add_argument("--val-session", type=int, default=None)
    ap.add_argument("--all", action="store_true", help="train on every session (final model for the board); "
                    "the reported accuracy is then on training data")
    ap.add_argument("--k", type=int, default=6)              # decay shift
    ap.add_argument("--reset", type=float, default=0.0)      # reset value, in units of threshold
    ap.add_argument("--slope", type=float, default=5.0)      # surrogate slope (threshold = 1)
    ap.add_argument("--lr", type=float, default=3e-3)
    ap.add_argument("--epochs", type=int, default=30)
    ap.add_argument("--batch", type=int, default=32)
    ap.add_argument("--lam", type=float, default=1e-3)       # hidden spike-count penalty
    ap.add_argument("--seed", type=int, default=0)
    args = ap.parse_args()

    torch.manual_seed(args.seed)
    np.random.seed(args.seed)

    # ---------------- data ----------------
    if args.data:
        raw, y, sess = data.load_recordings(args.data)
        vs = args.val_session if args.val_session is not None else sess.max()
        tr, va = sess != vs, sess == vs
        if args.all:
            tr = va = np.ones(len(y), bool)
        raw_tr, y_tr, raw_va, y_va = raw[tr], y[tr], raw[va], y[va]
    else:
        raw_tr, y_tr, _ = data.make_synthetic(160, seed=1)
        raw_va, y_va, _ = data.make_synthetic(40, seed=2)
    x_tr = data.encode(raw_tr).astype(np.float32)
    x_va = data.encode(raw_va).astype(np.float32)
    print(f"train {len(y_tr)}  val {len(y_va)}  T={x_tr.shape[1]}  inputs={x_tr.shape[2]}  "
          f"input spike prob={x_tr.mean():.4f}")
    assert x_tr.shape[2] == netshape[0], "encoder width must match netshape[0]"

    Xtr, Ytr = torch.from_numpy(x_tr), torch.from_numpy(y_tr).long()
    Xva = torch.from_numpy(x_va)

    # ---------------- model ----------------
    model = TrainSNN(args.k, 1.0, args.reset, list(netshape), args.slope)
    p_in = max(float(x_tr.mean()), 1e-3)
    model.init_weights(fire_rate=p_in, std_gain=1.0, mean_gain=0.0)
    print("calibrating on a training batch:")
    calibrate(model, Xtr[torch.randperm(len(Xtr))[:128]], targets=[0.03, 0.01])

    opt = torch.optim.Adam(model.parameters(), lr=args.lr)
    T = Xtr.shape[1]

    # ---------------- train ----------------
    for ep in range(args.epochs):
        model.train()
        perm = torch.randperm(len(Xtr))
        tot, n = 0.0, 0
        for b in range(0, len(perm), args.batch):
            idx = perm[b:b + args.batch]
            counts = model(Xtr[idx])
            loss = F.cross_entropy(counts[-1], Ytr[idx])
            loss = loss + args.lam * sum(c.mean() for c in counts[:-1])
            opt.zero_grad()
            loss.backward()
            opt.step()
            tot += loss.item() * len(idx)
            n += len(idx)
        with torch.no_grad():
            cv = model(Xva)
        hid = cv[0].mean().item() / T
        print(f"epoch {ep:3d}  loss {tot / n:.4f}  val acc {accuracy(cv[-1].numpy(), y_va):.3f}  "
              f"hidden rate {hid:.4f}")

    # ---------------- quantise + integer check ----------------
    Wf = [w.detach().numpy() for w in model.W]
    Wq, thr, rst, scale = quantize(Wf, 1.0, args.reset, args.k)
    with torch.no_grad():
        acc_f = accuracy(model(Xva)[-1].numpy(), y_va)
    counts_i, imax, vmax = run_int(x_va.astype(np.uint8), Wq, thr, rst, args.k)
    acc_i = accuracy(counts_i[-1], y_va)
    ops = sum(c.sum() for c in counts_i[:-1]) * netshape[2] + x_va.sum() * netshape[1]
    print(f"\nscale {scale:g}  threshold_int {thr}  reset_int {rst}  k {args.k}")
    print(f"max |w_int| {max(int(np.abs(w).max()) for w in Wq)}  max |I| {imax} (< 2^22)  "
          f"max |V| {vmax} (< 2^24)")
    print(f"val accuracy  float {acc_f:.3f}   integer {acc_i:.3f}")
    print(f"synaptic ops per window (integer model): {ops / len(y_va):.0f}   "
          f"dense ANN equivalent: {T * (netshape[0] * netshape[1] + netshape[1] * netshape[2])}")

    cm = np.zeros((netshape[2], netshape[2]), int)
    for t_, p_ in zip(y_va, np.argmax(counts_i[-1], axis=1)):
        cm[t_, p_] += 1
    print("confusion (rows = true, cols = predicted):", *data.CLASSES, sep="\n  ")
    print(cm)

    np.savez("weights_int.npz", **{f"W{i}": w for i, w in enumerate(Wq)},
             threshold=thr, reset=rst, k=args.k, scale=scale,
             steps=np.array(data.STEPS), netshape=np.array(netshape))
    print("saved weights_int.npz")


if __name__ == "__main__":
    main()
