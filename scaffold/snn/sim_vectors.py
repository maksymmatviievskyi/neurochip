"""
Test vectors for scaffold/tb/de10_top_tb.sv: one recorded 1024-sample window and the readout decisions the
board must make on it (bit-exact integer model of dencode + snn + readout).

    python sim_vectors.py recordings/s2_double_tap.mif --window 3 --out ../tb/run
writes  samples.hex   x, y, z per line (48-bit hex, what the fake ADXL345 sends)
        expected.txt  "t class top" for every decision (t = timestep index, top = winning count)
"""
import argparse
import os
import numpy as np

import import_recordings as ir
import train_live as tl


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mif")
    ap.add_argument("--window", type=int, default=0)
    ap.add_argument("--weights", default="weights_live.npz")
    ap.add_argument("--out", default=".")
    args = ap.parse_args()

    w = np.load(args.weights)
    Wq = [w[f"W{i}"] for i in range(len(w["netshape"]) - 1)]
    thr, rst, k = int(w["threshold"]), int(w["reset"]), int(w["k"])
    xyz = ir.unpack(ir.read_mif(args.mif))
    raw = xyz[args.window * ir.WIN:(args.window + 1) * ir.WIN]
    assert raw.any(), "empty window"

    os.makedirs(args.out, exist_ok=True)
    with open(os.path.join(args.out, "samples.hex"), "w") as f:
        for x, y, z in raw:
            f.write(f"{int(x) & 0xFFFF:04x}{int(y) & 0xFFFF:04x}{int(z) & 0xFFFF:04x}\n")

    dec = tl.stream_decisions_full(raw, Wq, thr, rst, k)
    with open(os.path.join(args.out, "expected.txt"), "w") as f:
        for t, c, top in dec:
            f.write(f"{t} {c} {top}\n")

    # gesture events exactly as readout.sv: peak of each run of non-idle decisions
    events, cur = [], None
    for t, c, top in dec:
        if c != 0:
            if cur is None or top > cur[1]:
                cur = (c, top)
        elif cur is not None:
            events.append(cur[0]); cur = None
    names = [tl.data.CLASSES[c] for c in events]
    print(f"{args.mif} window {args.window}: {len(dec)} decisions, gesture results: {names or 'none'}"
          + (f" (still in a gesture at the end: {tl.data.CLASSES[cur[0]]})" if cur else ""))


if __name__ == "__main__":
    main()
