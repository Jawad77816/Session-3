#!/usr/bin/env python3
"""Convert a YouTube auto-caption .srt into clean, continuous text.

YouTube auto-captions use a rolling window: each cue repeats the tail of
the previous cue plus a few new words. A naive concatenation is therefore
extremely repetitive. This script strips indices/timestamps/inline tags and
merges consecutive cues by removing the overlapping region (word-based
longest tail/head match), producing readable prose.

Usage: python3 -I clean_srt.py <input.srt> <output.txt>
"""
import re
import sys


def parse_srt(path):
    with open(path, encoding="utf-8") as f:
        content = f.read()
    cues = []
    for block in re.split(r"\n\s*\n", content.strip()):
        lines = [ln for ln in block.splitlines() if ln.strip()]
        if not lines:
            continue
        if re.match(r"^\d+$", lines[0].strip()):   # index line
            lines = lines[1:]
        if lines and "-->" in lines[0]:            # timestamp line
            lines = lines[1:]
        text = " ".join(lines)
        text = re.sub(r"<[^>]+>", "", text)        # inline tags
        text = re.sub(r"\s+", " ", text).strip()
        if text:
            cues.append(text)
    return cues


def merge_overlap(acc_words, nxt):
    """Append nxt onto acc_words, dropping the overlapping prefix of nxt
    that duplicates the tail of acc_words."""
    b = nxt.split()
    if not acc_words:
        return b
    max_ov = min(len(acc_words), len(b))
    for k in range(max_ov, 0, -1):
        if acc_words[-k:] == b[:k]:
            return acc_words + b[k:]
    return acc_words + b


def main():
    if len(sys.argv) != 3:
        sys.exit("usage: clean_srt.py <input.srt> <output.txt>")
    src, dst = sys.argv[1], sys.argv[2]
    cues = parse_srt(src)
    # drop exact consecutive duplicates first
    deduped = []
    for c in cues:
        if not deduped or deduped[-1] != c:
            deduped.append(c)
    words = []
    for c in deduped:
        words = merge_overlap(words, c)
    text = " ".join(words).strip()
    # sentence-ish wrapping on Urdu full stop (۔) and Latin punctuation
    text = re.sub(r"([۔?!])\s+", r"\1\n", text)
    with open(dst, "w", encoding="utf-8") as f:
        f.write(text + "\n")
    print(f"  cleaned -> {dst} ({len(words)} words)")


if __name__ == "__main__":
    main()
