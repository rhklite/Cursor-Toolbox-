#!/usr/bin/env python3
"""Capture UDP JSON signals and fuzzy-match candidate signal paths."""

from __future__ import annotations

import argparse
import json
import socket
import time
from difflib import SequenceMatcher
from pathlib import Path
from typing import Any


def flatten_paths(obj: Any, prefix: str = "") -> list[str]:
    """Flatten nested JSON keys into PlotJuggler-friendly paths."""
    out: list[str] = []
    if isinstance(obj, dict):
        for key, value in obj.items():
            path = f"{prefix}/{key}" if prefix else f"/{key}"
            out.extend(flatten_paths(value, path))
    elif isinstance(obj, list):
        for idx, value in enumerate(obj):
            path = f"{prefix}[{idx}]"
            out.extend(flatten_paths(value, path))
    else:
        if prefix:
            out.append(prefix)
    return out


def normalize_name(value: str) -> str:
    return (
        value.lower()
        .replace("_", "")
        .replace("-", "")
        .replace(".", "")
        .replace("/", "")
        .replace(" ", "")
        .replace("[", "")
        .replace("]", "")
    )


def similarity_score(query: str, candidate: str) -> float:
    """Combined score that favors character and token similarity."""
    nq = normalize_name(query)
    nc = normalize_name(candidate)
    if not nq or not nc:
        return 0.0

    char_score = SequenceMatcher(None, nq, nc).ratio()

    query_tokens = {t for t in query.lower().replace("/", " ").replace(".", " ").replace("_", " ").split() if t}
    candidate_tokens = {t for t in candidate.lower().replace("/", " ").replace(".", " ").replace("_", " ").split() if t}
    if query_tokens and candidate_tokens:
        overlap = len(query_tokens.intersection(candidate_tokens)) / len(query_tokens)
    else:
        overlap = 0.0

    return 0.85 * char_score + 0.15 * overlap


def parse_fuzzy_file(path: Path) -> list[str]:
    """Read fuzzy names from a text file (one per line) or JSON list."""
    raw = path.read_text(encoding="utf-8").strip()
    if not raw:
        return []
    if raw.startswith("["):
        data = json.loads(raw)
        if not isinstance(data, list):
            raise ValueError("JSON fuzzy file must be a list of strings.")
        return [str(item).strip() for item in data if str(item).strip()]
    return [line.strip() for line in raw.splitlines() if line.strip() and not line.strip().startswith("#")]


def capture_udp_json(ip: str, port: int, seconds: float) -> tuple[set[str], int, int]:
    """Capture UDP JSON packets and extract unique leaf paths."""
    seen_paths: set[str] = set()
    packets = 0
    parse_failures = 0

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind((ip, port))
    sock.settimeout(0.5)

    start = time.time()
    while time.time() - start < seconds:
        try:
            payload, _ = sock.recvfrom(65535)
            packets += 1
            decoded = payload.decode("utf-8", errors="ignore")
            parsed = json.loads(decoded)
            for path in flatten_paths(parsed):
                seen_paths.add(path)
        except socket.timeout:
            continue
        except Exception:
            parse_failures += 1

    sock.close()
    return seen_paths, packets, parse_failures


def match_candidates(query: str, candidates: list[str], topn: int) -> list[dict[str, Any]]:
    scored = []
    for path in candidates:
        score = similarity_score(query, path)
        scored.append({"path": path, "score": round(score, 4)})
    scored.sort(key=lambda item: item["score"], reverse=True)
    return scored[:topn]


def main() -> None:
    parser = argparse.ArgumentParser(description="Capture UDP JSON signals and fuzzy-match names.")
    parser.add_argument("--ip", default="0.0.0.0", help="UDP bind IP (default: 0.0.0.0)")
    parser.add_argument("--port", required=True, type=int, help="UDP bind port")
    parser.add_argument("--seconds", default=10.0, type=float, help="Capture duration in seconds")
    parser.add_argument("--topn", default=5, type=int, help="Top N candidates per fuzzy signal")
    parser.add_argument("--threshold", default=0.85, type=float, help="Auto-accept score threshold")
    parser.add_argument("--fuzzy-file", required=True, help="Text or JSON file containing fuzzy names")
    parser.add_argument("--out-json", default="", help="Optional output JSON file path")
    args = parser.parse_args()

    fuzzy_names = parse_fuzzy_file(Path(args.fuzzy_file))
    if not fuzzy_names:
        raise SystemExit("No fuzzy names found. Provide non-empty --fuzzy-file.")

    seen_paths, packets, parse_failures = capture_udp_json(args.ip, args.port, args.seconds)
    sorted_paths = sorted(seen_paths)

    results: list[dict[str, Any]] = []
    accepted: dict[str, dict[str, Any]] = {}

    for fuzzy in fuzzy_names:
        matches = match_candidates(fuzzy, sorted_paths, args.topn)
        entry = {"fuzzy": fuzzy, "candidates": matches}
        results.append(entry)
        if matches and matches[0]["score"] >= args.threshold:
            accepted[fuzzy] = {"exact": matches[0]["path"], "score": matches[0]["score"]}

    report = {
        "config": {
            "ip": args.ip,
            "port": args.port,
            "seconds": args.seconds,
            "topn": args.topn,
            "threshold": args.threshold,
        },
        "stats": {
            "packets_received": packets,
            "json_parse_failures": parse_failures,
            "unique_signal_paths": len(sorted_paths),
        },
        "observed_paths": sorted_paths,
        "results": results,
        "accepted": accepted,
    }

    print(f"packets_received: {packets}")
    print(f"json_parse_failures: {parse_failures}")
    print(f"unique_signal_paths: {len(sorted_paths)}")
    print()

    for item in results:
        print(f"fuzzy: {item['fuzzy']}")
        if not item["candidates"]:
            print("  (no candidates)")
            print()
            continue
        for candidate in item["candidates"]:
            marker = " (auto)" if candidate["score"] >= args.threshold and candidate is item["candidates"][0] else ""
            print(f"  {candidate['score']:.4f}  {candidate['path']}{marker}")
        print()

    if args.out_json:
        out_path = Path(args.out_json)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        out_path.write_text(json.dumps(report, indent=2), encoding="utf-8")
        print(f"wrote_json: {out_path}")


if __name__ == "__main__":
    main()
