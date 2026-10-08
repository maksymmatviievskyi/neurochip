"""
Conventional baseline: a small 1D CNN on the same raw accelerometer data, same sessions, same live protocol
(decision every D=32 samples over the last W=256 samples, gesture result = peak non-idle decision).
Reports accuracy and multiply-accumulates (MACs) next to the SNN's measured synaptic operations.

    python cnn_baseline.py recordings/*.mif
"""
import argparse
import numpy as np
import torch
import torch.nn as nn
import torch.nn.functional as F

import data
import train_live as tl

W, D = tl.W, tl.D


class CNN(nn.Module):
    def __init__(self, c1=16, c2=32, c3=32):
        super().__init__()
        self.convs = nn.ModuleList([nn.Conv1d(3, c1, 7, stride=2, padding=3),
                                    nn.Conv1d(c1, c2, 5, stride=2, padding=2),
                                    nn.Conv1d(c2, c3, 5, stride=2, padding=2)])
        self.fc = nn.Linear(c3, 5)

    def forward(self, x):                     # x: (B, 3, W) in g
        for c in self.convs:
            x = F.relu(c(x))
        return self.fc(x.mean(-1))

    def macs(self, L=W):
        m = 0
        for c in self.convs:
            L = (L + 2 * c.padding[0] - c.kernel_size[0]) // c.stride[0] + 1
            m += L * c.out_channels * c.in_channels * c.kernel_size[0]
        return m + self.fc.in_features * self.fc.out_features


def norm(raw):                                # counts -> g, remove gravity per window (mean)
    x = raw.astype(np.float32) / 256.0
    return x - x.mean(axis=-2, keepdims=True)


def crops(wins, rng, n_pos=10, n_neg=4):
    X, Y = [], []
    for s, label, win, f, l in wins:
        n = len(win)
        if label == 0:
            for st in rng.integers(0, n - W, n_pos + n_neg):
                X.append(win[st:st + W]); Y.append(0)
            continue
        lo, hi = max(0, l + 8 - W), min(n - W, f - 8)
        if hi < lo:
            lo = hi = int(np.clip((f + l) // 2 - W // 2, 0, n - W))
        for st in rng.integers(lo, hi + 1, n_pos):
            X.append(win[st:st + W]); Y.append(label)
        cands = list(range(0, max(0, f - 16 - W))) + list(range(l + 16, n - W))
        if cands:
            for st in rng.choice(cands, min(n_neg, len(cands)), replace=False):
                X.append(win[st:st + W]); Y.append(0)
    X = norm(np.stack(X)).transpose(0, 2, 1)
    return torch.from_numpy(np.ascontiguousarray(X)), torch.from_numpy(np.array(Y)).long()


def live_eval(model, wins):
    cm = np.zeros((5, 5), int)
    model.eval()
    for s, label, win, f, l in wins:
        starts = list(range(W - W, len(win) - W + 1, D))
        X = norm(np.stack([win[st:st + W] for st in starts])).transpose(0, 2, 1)
        with torch.no_grad():
            p = F.softmax(model(torch.from_numpy(np.ascontiguousarray(X))), -1).numpy()
        dec = [(int(q.argmax()), float(q.max())) for q in p]
        nz = [d for d in dec if d[0] != 0]
        pred = max(nz, key=lambda d: d[1])[0] if nz else 0
        cm[label, pred] += 1
    return np.trace(cm) / cm.sum(), cm


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    ap.add_argument("--epochs", type=int, default=60)
    args = ap.parse_args()
    wins = tl.load_windows(args.files)
    accs = []
    for vs in (2, 1):
        torch.manual_seed(0); rng = np.random.default_rng(0)
        tr = [w for w in wins if w[0] != vs]; va = [w for w in wins if w[0] == vs]
        X, Y = crops(tr, rng)
        model = CNN()
        opt = torch.optim.Adam(model.parameters(), lr=3e-3, weight_decay=1e-4)
        for ep in range(args.epochs):
            model.train()
            perm = torch.randperm(len(X))
            for b in range(0, len(X), 32):
                i = perm[b:b + 32]
                loss = F.cross_entropy(model(X[i]), Y[i])
                opt.zero_grad(); loss.backward(); opt.step()
        acc, cm = live_eval(model, va)
        accs.append(acc)
        print(f"CNN train on session {3 - vs} -> test session {vs}: live accuracy {acc:.3f}")
        print(cm)
    params = sum(p.numel() for p in model.parameters())
    print(f"CNN: {params} parameters, {model.macs()} MACs per inference, mean live accuracy {np.mean(accs):.3f}")


if __name__ == "__main__":
    main()
