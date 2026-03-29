# List Tracked Batches (User Command)

Show tracked Fuyao jobs grouped by batch (sweep_id), newest batches first.
Invoke as `/list-tracked-batches`.

## Source Of Truth

Always use the script below. Do not manually sort, group, or reformat in the agent.

```bash
python3 ~/.cursor/scripts/list_tracked_batches.py [args]
```

## Supported Arguments

- `--start-time "<time>"` inclusive lower bound on dispatched_at
- `--end-time "<time>"` inclusive upper bound on dispatched_at
- `--timezone "<iana_tz>"` timezone for parsing naive times and display (default `America/Los_Angeles`)
- `--output table|json` output mode (default `table`)
- `--server "<ssh_host>"` registry host (default `huh.desktop.us`)
- `--registry-path "<path>"` registry path on server

Accepted time formats:

- ISO datetime with timezone, for example `2026-03-28T05:30:00-07:00`
- `YYYY-MM-DD HH:MM[:SS]`
- `YYYY-MM-DD` (interpreted in selected timezone)

## Prompt Contract

When user does not provide filters:

1. Run with defaults (no time filter).

When user asks for filtering:

1. Ask only for missing values needed to run the command.
2. Keep default timezone unless user explicitly overrides it.

## Execution Contract

1. Build the script command from user-specified filters.
2. Run the script once.
3. Print script stdout verbatim.
4. If script exits nonzero, print stderr verbatim and stop.
