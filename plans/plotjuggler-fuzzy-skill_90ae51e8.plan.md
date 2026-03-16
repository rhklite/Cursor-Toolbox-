---
name: plotjuggler-fuzzy-skill
overview: Create a personal Cursor skill that standardizes generating PlotJuggler layout + streaming XML files by first resolving fuzzy signal names against live UDP JSON signals.
todos:
  - id: write-skill-md
    content: Draft SKILL.md with trigger terms, required workflow, and exact-name confirmation gates
    status: completed
  - id: build-matcher-script
    content: Create UDP JSON fuzzy-matching Python CLI utility with scoring and export
    status: completed
  - id: add-reference-doc
    content: Write reference.md with usage examples and troubleshooting
    status: completed
  - id: final-verify
    content: Check metadata, terminology consistency, and practical defaults
    status: completed
isProject: false
---

# Create PlotJuggler Fuzzy-Match Skill

## Goal

Build a personal skill that Cursor can automatically use when asked to create or modify PlotJuggler layout/streaming configs, with a required fuzzy-to-exact signal resolution step using a UDP JSON capture script.

## Scope

- Create a personal skill at `~/.cursor/skills/plotjuggler-udp-fuzzy/`.
- Include a concise `SKILL.md` with trigger phrases, workflow, and output contract.
- Include a Python utility script for UDP JSON signal discovery + fuzzy matching.
- Include a short reference file for script options and integration notes.

## Planned Files

- `~/.cursor/skills/plotjuggler-udp-fuzzy/SKILL.md`
- `~/.cursor/skills/plotjuggler-udp-fuzzy/scripts/match_udp_signals.py`
- `~/.cursor/skills/plotjuggler-udp-fuzzy/reference.md`

## Implementation Plan

1. Author `SKILL.md` with strict WHEN-to-use guidance:
  - Trigger on requests mentioning PlotJuggler, layout XML, streaming config, UDP signals, fuzzy signal names.
  - Require exact signal path resolution before final XML generation.
  - Define two operating modes: (a) fuzzy-only draft, (b) verified exact match from live stream.
2. Define workflow in `SKILL.md`:
  - Collect required inputs (UDP bind/port, capture duration, fuzzy names).
  - Run matching script to discover exact paths.
  - Produce a rename map (fuzzy -> exact + score).
  - Ask for confirmation on low-confidence matches.
  - Generate final layout and streaming XML using confirmed exact names.
3. Add `scripts/match_udp_signals.py`:
  - Listen to UDP packets, parse JSON payloads, flatten nested fields into canonical signal paths.
  - Normalize names (case, separators, punctuation) and compute similarity scores.
  - Output top-N candidates per fuzzy signal and optional threshold-based auto-accept set.
  - Provide CLI flags (`--ip`, `--port`, `--seconds`, `--topn`, `--threshold`, `--fuzzy-file`, `--out-json`).
4. Add `reference.md`:
  - Quick usage examples, expected JSON payload assumptions, troubleshooting (no packets, malformed JSON, sparse signals), and recommended thresholds.
5. Verify skill quality:
  - Ensure name/description format and concise content.
  - Ensure script paths use Unix-style paths and are directly executable with Python.
  - Ensure terminology is consistent (`signal path`, `rename map`, `layout XML`, `streaming XML`).

## Defaults Chosen

- Skill scope: Personal (`~/.cursor/skills/`).
- UDP payload default: JSON.
- Matching behavior: Suggest top 5 candidates; auto-accept only at/above threshold, otherwise request confirmation.

