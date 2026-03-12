# PlotJuggler UDP Fuzzy Match Reference

## Purpose

Use this script to discover exact signal paths from a live UDP JSON stream and map fuzzy names to likely matches before creating PlotJuggler XML files.

## Script

- Path: `scripts/match_udp_signals.py`
- Input: UDP JSON packets + fuzzy names file
- Output: ranked candidate paths and optional JSON report

## Fuzzy Names File Formats

### Text (one name per line)

```text
imu accel x
vehicle speed
yawrate
```

### JSON list

```json
["imu accel x", "vehicle speed", "yawrate"]
```

## Common Usage

Capture for 12 seconds on port `9870`:

```bash
python scripts/match_udp_signals.py \
  --port 9870 \
  --seconds 12 \
  --fuzzy-file fuzzy_names.txt
```

Write machine-readable report:

```bash
python scripts/match_udp_signals.py \
  --port 9870 \
  --seconds 12 \
  --fuzzy-file fuzzy_names.txt \
  --out-json output/match_report.json
```

Tune strictness:

```bash
python scripts/match_udp_signals.py \
  --port 9870 \
  --seconds 12 \
  --threshold 0.80 \
  --topn 8 \
  --fuzzy-file fuzzy_names.txt
```

## Recommended Thresholds

- `0.85`: safe default for auto-accepting top match
- `0.75-0.84`: usually good suggestions; confirm manually
- `< 0.75`: treat as unresolved unless user confirms

## UDP JSON Assumptions

- Packet payload is valid UTF-8 JSON object/array.
- Nested objects are flattened into slash paths (`/imu/accel/x`).
- Arrays are indexed (`/wheels[0]/speed`).
- Only leaf values become signal paths.

## Troubleshooting

- No matches:
  - Increase `--seconds`.
  - Verify `--port` and sender destination IP.
  - Check firewall/network path.
- Many JSON parse failures:
  - Stream may be binary or mixed payloads.
  - Add a custom parser or preprocessor for that stream.
- Wrong top candidate:
  - Increase `--topn`, lower threshold, then confirm manually.
  - Provide more specific fuzzy name tokens.

## Integration Notes

Before final PlotJuggler XML generation:
1. Build rename map from script output.
2. Confirm low-confidence mappings.
3. Use confirmed exact signal paths in both layout XML and streaming XML.
