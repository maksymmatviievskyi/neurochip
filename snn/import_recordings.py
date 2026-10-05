"""
Convert In-System Memory Content Editor dumps (.mif) of the recorder RAM into recordings.npz for train.py.

Recorder RAM layout (must match the RTL):
    16384 words x 48 bits, 16 windows of 1024 samples (2.56 s at 400 Hz)
    word = {x[15:0], y[15:0], z[15:0]}   signed, ADXL345 full-resolution counts (3.9 mg/LSB)
    window w = addresses w*1024 .. w*1024+1023; never-recorded windows are all zero (RAM cleared on reset)

File naming:  recordings/s<session>_<class>[_<anything>].mif     e.g. recordings/s1_hard_tap.mif
              <class> must be one of data.CLASSES

    python import_recordings.py recordings/*.mif --out recordings.npz
"""
import argparse
import os
import re
import numpy as np

import data

WORDS, WIN = 16384, 1024


def read_mif(path):
    words = np.zeros(WORDS, dtype=np.int64)
    width, in_content = 48, False
    radix = {"BIN": 2, "OCT": 8, "DEC": 10, "UNS": 10, "HEX": 16}
    arad, drad = 16, 16
    with open(path) as f:
        for line in f:
            line = line.split("--")[0].strip()
            if not line:
                continue
            m = re.match(r"WIDTH\s*=\s*(\d+)", line, re.I)
            if m:
                width = int(m.group(1))
            m = re.match(r"(ADDRESS|DATA)_RADIX\s*=\s*(\w+)", line, re.I)
            if m:
                r = radix[m.group(2).upper()]
                if m.group(1).upper() == "ADDRESS":
                    arad = r
                else:
                    drad = r
            if re.match(r"CONTENT\s+BEGIN", line, re.I):
                in_content = True
                continue
            if not in_content or re.match(r"END", line, re.I):
                continue
            m = re.match(r"\[?\s*([0-9A-Fa-f]+)\s*(?:\.\.\s*([0-9A-Fa-f]+)\s*\])?\s*:\s*([0-9A-Fa-f\s]+);", line)
            if not m:
                continue
            a0 = int(m.group(1), arad)
            a1 = int(m.group(2), arad) if m.group(2) else a0
            vals = [int(v, drad) for v in m.group(3).split()]
            if len(vals) == 1:
                words[a0:a1 + 1] = vals[0]
            else:                                   # "addr : v0 v1 v2 ..." form
                words[a0:a0 + len(vals)] = vals
    assert width == 48, f"{path}: expected WIDTH=48, got {width}"
    return words


def unpack(words):
    def s16(v):
        v = v & 0xFFFF
        return np.where(v >= 0x8000, v - 0x10000, v)
    return np.stack([s16(words >> 32), s16(words >> 16), s16(words)], axis=1)   # (WORDS, 3)


def crop(win, label, rng, n_crops, T=data.T):
    """
    Cut T-sample examples out of a 1024-sample recording exactly where the board's trigger would
    (data.hw_windows), so training sees the same window placement as the live hardware.
    Extra crops (n_crops > 1) are the same windows shifted by a few samples, for robustness.
    Idle recordings also get random crops, since the trigger rarely fires when nothing happens.
    """
    out = []
    starts = data.hw_windows(win)
    if label != 0:
        # a tap is one event: later triggers in the same recording are its tail / handling noise.
        # a shake is long and legitimately triggers several windows.
        starts = starts[:3 if data.CLASSES[label] == "shake" else 1]
    for s0 in starts:
        for c in range(n_crops):
            s = s0 if c == 0 else s0 + int(rng.integers(-8, 9))
            s = int(np.clip(s, 0, len(win) - T))
            out.append(win[s:s + T])
    if label == 0:
        for _ in range(n_crops):
            s = int(rng.integers(0, len(win) - T))
            out.append(win[s:s + T])
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    ap.add_argument("--out", default="recordings.npz")
    ap.add_argument("--crops", type=int, default=3)
    args = ap.parse_args()
    rng = np.random.default_rng(0)

    raws, labels, sessions = [], [], []
    for path in sorted(args.files):
        m = re.match(r"s(\d+)_(.+)\.mif$", os.path.basename(path), re.I)
        rest = m.group(2) if m else ""
        hits = [c for c in data.CLASSES if rest == c or rest.startswith(c + "_")]
        name = max(hits, key=len) if hits else None
        if not m or name is None:
            print(f"skip {path}: name must be s<session>_<class>.mif, class in {data.CLASSES}")
            continue
        sess, label = int(m.group(1)), data.CLASSES.index(name)
        xyz = unpack(read_mif(path))
        used = missed = 0
        for w in range(WORDS // WIN):
            win = xyz[w * WIN:(w + 1) * WIN]
            if not win.any():
                continue                             # never recorded
            crops = crop(win, label, rng, args.crops)
            if not crops:
                missed += 1                          # no gesture found in this window
                continue
            for c in crops:
                raws.append(c); labels.append(label); sessions.append(sess)
            used += 1
        print(f"{path}: session {sess}, {name}, {used} windows used, {missed} without a gesture")

    raw = np.stack(raws).astype(np.int16)
    np.savez(args.out, raw=raw, labels=np.array(labels), session=np.array(sessions))
    print(f"saved {args.out}: {len(labels)} examples, classes {np.bincount(labels, minlength=len(data.CLASSES))}")

    still = [r for r, l in zip(raw, labels) if l == 0]
    if still:
        sd = np.diff(np.stack(still).astype(float), axis=1).std(axis=(0, 1)) / np.sqrt(2)
        print(f"idle noise per axis (LSB): {np.round(sd, 2)}  -> smallest encoder step ~ {4 * sd.max():.0f}")


if __name__ == "__main__":
    main()
