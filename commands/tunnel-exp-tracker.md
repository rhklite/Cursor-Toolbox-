# Exp-Tracker Tunnel

Manage the resilient SSH tunnel to huh.desktop.us that forwards port 8765 (experiment tracker dashboard).

Invoke as `/tunnel-exp-tracker`.

## Subcommands

Run `~/.cursor/scripts/tunnel_exp_tracker.sh <subcommand>`:

- `start` — bootstrap the launchd agent (no-op if already running)
- `stop` — bootout the launchd agent
- `restart` — stop then start
- `status` — show launchd job state + whether port 8765 is locally bound
- `logs` — tail the tunnel log at ~/Library/Logs/exp-tracker-tunnel.log

## Natural Language Mapping

- "start / connect / enable tunnel" → `start`
- "stop / kill / disconnect tunnel" → `stop`
- "restart / reconnect tunnel" → `restart`
- "tunnel status / is tunnel up / check tunnel" → `status`
- "tunnel logs / show logs" → `logs`

## Notes

- The tunnel auto-reconnects via launchd KeepAlive (ThrottleInterval=30s); manual restart is rarely needed.
- Dashboard is at http://localhost:8765 when VPN is up and tunnel is connected.
