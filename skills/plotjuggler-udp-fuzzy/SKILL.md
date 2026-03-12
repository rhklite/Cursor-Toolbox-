---
name: plotjuggler-udp-fuzzy
description: Generates and updates PlotJuggler layout XML and streaming XML using UDP JSON signals. Use when the user mentions PlotJuggler, layout files, streaming config, UDP telemetry, fuzzy signal names, or wants fuzzy-to-exact signal mapping.
---

# PlotJuggler UDP Fuzzy Match

## When To Use

Apply this skill when requests involve:
- PlotJuggler layout XML creation or modification
- PlotJuggler streaming XML creation or modification
- UDP data source setup
- Fuzzy signal names that must be mapped to exact signal paths

## Required Inputs

Collect these inputs before generating final XML:
- UDP bind IP (default `0.0.0.0`)
- UDP port
- Capture duration in seconds
- Fuzzy signal names (or exact names if already known)
- Desired plot arrangement (tabs, plots, signal grouping)

If the user has not provided plot arrangement yet, generate only a signal mapping draft first.

## Operating Modes

1. **Fuzzy Draft Mode**
   - Use when only fuzzy names are available.
   - Produce candidate mappings and confidence scores.
   - Do not claim names are exact.

2. **Verified Exact Mode**
   - Use after checking a live UDP JSON stream.
   - Confirm or auto-accept mappings above threshold.
   - Use only confirmed exact signal paths in final XML.

## Workflow

1. Parse user intent: new files vs edits to existing PlotJuggler XML.
2. If names are fuzzy, run:
   - `python scripts/match_udp_signals.py --port <port> --seconds <n> --fuzzy-file <file>`
3. Build a rename map: `fuzzy_name -> exact_path (score)`.
4. For low-confidence matches, ask user confirmation before XML generation.
5. Generate/update:
   - PlotJuggler layout XML
   - PlotJuggler streaming XML
6. Keep naming terminology consistent: `signal path`, `rename map`, `layout XML`, `streaming XML`.

## Confidence Gate

Use this policy unless user overrides:
- score `>= 0.85`: auto-accept
- score `0.70-0.84`: propose, request confirmation
- score `< 0.70`: do not map automatically

## Output Contract

When finishing a request, return:
1. Confirmed signal paths list
2. Rename map table with scores
3. Any unresolved fuzzy names
4. The generated or modified layout XML and streaming XML artifacts

## Utility Script

Use `scripts/match_udp_signals.py` for UDP JSON capture and fuzzy matching.
For options and troubleshooting, read [reference.md](reference.md).
