#!/usr/bin/env python3
"""Create short plain-English diff summaries for two files.

Output constraints:
- max 5 bullets
- max 10 words per bullet
"""

from __future__ import annotations

import argparse
import difflib
from pathlib import Path


MAX_BULLETS = 5
MAX_WORDS = 10


def read_lines(path: Path) -> list[str]:
    if not path.exists():
        return []
    try:
        return path.read_text(encoding="utf-8").splitlines()
    except UnicodeDecodeError:
        return path.read_text(encoding="utf-8", errors="replace").splitlines()


def clamp_words(text: str, max_words: int = MAX_WORDS) -> str:
    words = text.strip().split()
    if len(words) <= max_words:
        return " ".join(words)
    return " ".join(words[:max_words])


def build_summary(left_lines: list[str], right_lines: list[str]) -> list[str]:
    if left_lines == right_lines:
        return ["Files are identical."]

    bullets: list[str] = []
    if len(left_lines) != len(right_lines):
        bullets.append(
            f"Line count differs: {len(left_lines)} vs {len(right_lines)}."
        )

    first_diff = None
    for idx, (lval, rval) in enumerate(zip(left_lines, right_lines), start=1):
        if lval != rval:
            first_diff = idx
            break
    if first_diff is None:
        first_diff = min(len(left_lines), len(right_lines)) + 1
    bullets.append(f"First difference appears at line {first_diff}.")

    delta = list(difflib.ndiff(left_lines, right_lines))
    adds = sum(1 for line in delta if line.startswith("+ "))
    removes = sum(1 for line in delta if line.startswith("- "))
    if adds or removes:
        bullets.append(f"Changed lines: +{adds} and -{removes}.")

    changed_examples = []
    for line in delta:
        if line.startswith("+ ") or line.startswith("- "):
            text = line[2:].strip()
            if not text:
                continue
            changed_examples.append(text)
        if len(changed_examples) >= 2:
            break

    for example in changed_examples:
        bullets.append(f"Example change mentions: {example[:48]}.")
        if len(bullets) >= MAX_BULLETS:
            break

    cleaned = []
    for bullet in bullets[:MAX_BULLETS]:
        cleaned.append(clamp_words(bullet))

    return cleaned[:MAX_BULLETS]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--left-file", required=True)
    parser.add_argument("--right-file", required=True)
    parser.add_argument("--left-label", default="left")
    parser.add_argument("--right-label", default="right")
    args = parser.parse_args()

    left_file = Path(args.left_file).expanduser()
    right_file = Path(args.right_file).expanduser()
    left_lines = read_lines(left_file)
    right_lines = read_lines(right_file)
    bullets = build_summary(left_lines, right_lines)

    print(f"{args.left_label} vs {args.right_label}:")
    for bullet in bullets:
        print(f"- {bullet}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
