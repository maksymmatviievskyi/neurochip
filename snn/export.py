"""
Export a trained integer network (weights_int.npz) and test stimuli for the RTL inference testbench
(hw/tb/acc/snn_infer_tb.sv). The expected outputs come from the integer model (snn_int.py), so the
testbench checks that the RTL reproduces Python bit for bit.

    python export.py --data recordings.npz --session 2 --n 40

Neuron numbering in hardware (layers are contiguous ranges):
    layer 0 (inputs)  : 0 .. n0-1
    layer 1 (hidden)  : n0 .. n0+n1-1
    layer 2 (outputs) : n0+n1 .. n0+n1+n2-1
Connections are stored grouped by source neuron (CSR); zero weights are skipped.

Files written to --out (default ../hw/tb/acc/data):
    params.hex   n_layers, n_conn, n_examples, T, n_out, out_start   (one value per line)
    layers.hex   per layer: {start[7:0], count[7:0], threshold[15:0], decay[3:0], reset[15:0]}
    nmeta.hex    per neuron (128): {start[11:0], count[12:0]}
    conn.hex     per connection: {src[6:0], dst[6:0], weight[15:0]}
    stim.hex     per example, per timestep: 128-bit input spike vector
    expected.hex per example: output spike counts, 16 bits each, output 0 in the low bits
"""
import argparse
import os
import numpy as np

import data
from snn_int import run_int

MAX_NEURONS, MAX_CONN, T_MAX = 128, 4096, None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--weights", default="weights_int.npz")
    ap.add_argument("--data", default="recordings.npz")
    ap.add_argument("--session", type=int, default=None, help="session to take examples from (default: last)")
    ap.add_argument("--n", type=int, default=40, help="number of examples")
    ap.add_argument("--out", default=os.path.join("..", "hw", "tb", "acc", "data"))
    ap.add_argument("--rom", default=os.path.join("..", "hw", "syn", "de10_snn", "load.hex"),
                    help="weight ROM for the board (snn_live.sv)")
    ap.add_argument("--live", nargs="*", default=[], help=".mif recordings for the live testbench")
    ap.add_argument("--live-per-file", type=int, default=2)
    ap.add_argument("--live-out", default=os.path.join("..", "hw", "tb", "live", "data"))
    args = ap.parse_args()

    w = np.load(args.weights)
    Wq = [w[f"W{i}"] for i in range(len(w["netshape"]) - 1)]
    thr, rst, k = int(w["threshold"]), int(w["reset"]), int(w["k"])
    shape = [int(s) for s in w["netshape"]]
    assert tuple(w["steps"]) == tuple(data.STEPS), "weights were trained with different encoder steps"
    starts = np.cumsum([0] + shape[:-1])
    assert sum(shape) <= MAX_NEURONS

    # ---------------- network ----------------
    conns = []                                   # (src, dst, w)
    for l, W in enumerate(Wq):                   # W: (n_out, n_in)
        for i in range(W.shape[1]):
            for j in range(W.shape[0]):
                if W[j, i] != 0:
                    conns.append((starts[l] + i, starts[l + 1] + j, int(W[j, i])))
    conns.sort(key=lambda c: c[0])               # CSR: grouped by source
    assert len(conns) <= MAX_CONN, f"{len(conns)} connections > {MAX_CONN}"
    nstart = np.zeros(MAX_NEURONS, int)
    ncount = np.zeros(MAX_NEURONS, int)
    for idx, (s, _, _) in enumerate(conns):
        if ncount[s] == 0:
            nstart[s] = idx
        ncount[s] += 1

    # ---------------- stimuli + expected (integer model) ----------------
    raw, y, sess = data.load_recordings(args.data)
    s = args.session if args.session is not None else sess.max()
    sel = np.flatnonzero(sess == s)
    rng = np.random.default_rng(0)
    sel = np.sort(rng.choice(sel, size=min(args.n, len(sel)), replace=False))
    x = data.encode(raw[sel])                    # (N, T, n_in)
    counts, _, _ = run_int(x, Wq, thr, rst, k)
    out_counts = counts[-1]
    N, T, n_in = x.shape

    os.makedirs(args.out, exist_ok=True)
    p = lambda name: os.path.join(args.out, name)
    with open(p("params.hex"), "w") as f:
        for v in (len(shape), len(conns), N, T, shape[-1], starts[-1]):
            f.write(f"{v:08x}\n")
    with open(p("layers.hex"), "w") as f:
        for l in range(len(shape)):
            word = (int(starts[l]) << 52) | (shape[l] << 44) | ((thr & 0xFFFF) << 28) | ((k & 0xF) << 24) \
                   | ((rst & 0xFFFF) << 8)
            f.write(f"{word:016x}\n")
    with open(p("nmeta.hex"), "w") as f:
        for n in range(MAX_NEURONS):
            f.write(f"{(nstart[n] << 13) | ncount[n]:07x}\n")
    with open(p("conn.hex"), "w") as f:
        for s_, d_, w_ in conns:
            f.write(f"{(s_ << 23) | (d_ << 16) | (w_ & 0xFFFF):08x}\n")
    with open(p("stim.hex"), "w") as f:
        for e in range(N):
            for t in range(T):
                v = 0
                for i in np.flatnonzero(x[e, t]):
                    v |= 1 << int(i)
                f.write(f"{v:032x}\n")
    with open(p("expected.hex"), "w") as f:
        for e in range(N):
            v = 0
            for c in range(shape[-1]):
                v |= int(out_counts[e, c]) << (16 * c)
            f.write(f"{v:020x}\n")

    # ---------------- weight ROM for the board ----------------
    if args.rom:
        cmds = []
        for l in range(len(shape)):
            cmds.append((0, l, ((thr & 0xFFFF) << 32) | ((k & 0xF) << 28) | ((rst & 0xFFFF) << 12) | len(shape)))
        for l in range(len(shape)):
            cmds.append((1, l, (int(starts[l]) << 8) | shape[l]))
        for n in range(MAX_NEURONS):
            cmds.append((2, n, (int(nstart[n]) << 13) | int(ncount[n])))
        for c, (s_, d_, w_) in enumerate(conns):
            cmds.append((3, c, (s_ << 23) | (d_ << 16) | (w_ & 0xFFFF)))
        os.makedirs(os.path.dirname(args.rom) or ".", exist_ok=True)
        with open(args.rom, "w") as f:
            f.write(f"{(len(cmds) << 48) | (int(starts[-1]) << 40) | (int(shape[-1]) << 32):016x}\n")
            for t_, a_, p_ in cmds:
                f.write(f"{(int(t_) << 62) | (int(a_) << 48) | int(p_):016x}\n")
        assert len(cmds) + 1 <= 4096, "ROM too small"
        print(f"weight ROM: {len(cmds)} write commands -> {args.rom}")

    # ---------------- live testbench data: whole recordings through trigger + window ----------------
    if args.live:
        import import_recordings as ir
        recs, exp = [], []
        for path in args.live:
            xyz = ir.unpack(ir.read_mif(path))
            for w_ in range(ir.WORDS // ir.WIN):
                win = xyz[w_ * ir.WIN:(w_ + 1) * ir.WIN]
                if not win.any():
                    continue
                if sum(1 for r in recs if r[0] == path) >= args.live_per_file:
                    break
                recs.append((path, win))
        for r_idx, (_, win) in enumerate(recs):
            for st in data.hw_windows(win):
                cnt, _, _ = run_int(data.encode(win[None, st:st + data.T]), Wq, thr, rst, k)
                exp.append((r_idx, st, cnt[-1][0]))
        os.makedirs(args.live_out, exist_ok=True)
        q = lambda name: os.path.join(args.live_out, name)
        with open(q("raw.hex"), "w") as f:
            for _, win in recs:
                for x_, y_, z_ in win.astype(np.int64):
                    f.write(f"{((x_ & 0xFFFF) << 32) | ((y_ & 0xFFFF) << 16) | (z_ & 0xFFFF):012x}\n")
        with open(q("expected.hex"), "w") as f:     # {rec[15:0], start[15:0], 8 x count[8:0]}
            for r_idx, st, cnt in exp:
                v = (int(r_idx) << 88) | (int(st) << 72)
                for c_, n_ in enumerate(cnt):
                    v |= int(n_) << (9 * c_)
                f.write(f"{v:026x}\n")
        with open(q("params.hex"), "w") as f:
            f.write(f"{len(recs):08x}\n{len(exp):08x}\n")
        names = [os.path.basename(r[0]) for r in recs]
        print(f"live testbench: {len(recs)} recordings ({', '.join(sorted(set(names)))}), "
              f"{len(exp)} expected windows -> {args.live_out}")

    pred = np.argmax(out_counts, axis=1)
    print(f"exported {len(conns)} connections, {N} examples x {T} timesteps from session {s} -> {args.out}")
    print(f"integer-model accuracy on these examples: {(pred == y[sel]).mean():.3f}")
    with open(p("labels.txt"), "w") as f:
        f.write("\n".join(f"{data.CLASSES[y[i]]} {data.CLASSES[q]}" for i, q in zip(sel, pred)))


if __name__ == "__main__":
    main()
