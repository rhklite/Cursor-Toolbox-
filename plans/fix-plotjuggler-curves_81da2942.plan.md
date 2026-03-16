---
name: fix-plotjuggler-curves
overview: Fix PlotJuggler curve auto-population by adding a root-level `timestamp` field to the UDP JSON payload and verifying the complete data flow end-to-end.
todos:
  - id: add-root-timestamp
    content: Add root-level timestamp field to RobotData dataclass and __init__
    status: completed
  - id: sync-and-rerun
    content: scp updated robot_data.py to remote, re-run launcher, start UDP streamer, confirm curves populate
    status: completed
isProject: false
---

# Fix PlotJuggler Curve Auto-Population

## Root cause analysis

PlotJuggler's UDP JSON plugin receives data but curves don't populate. The live UDP packet capture confirmed signal paths match the XML curve names (both use `/learning/...` style with leading `/`). The problem is the **missing root-level `timestamp`**.

PlotJuggler's UDP JSON parser requires a `timestamp` field at the **top level** of the JSON object to use as the X-axis. The official PlotJuggler example (`udp_client.py`) demonstrates this:

```python
data = {
    "timestamp": time,        # <-- ROOT-LEVEL timestamp
    "test_data": { "cos": ..., "sin": ... }
}
```

The `RobotData.asdict()` output currently has this structure:

```json
{
  "state": { "timestamp": 1000042.3, ... },
  "control_input": { "timestamp": 1000042.3, ... },
  "control_output": { "timestamp": 1000042.3, ... },
  "learning": { ... }
}
```

There is **no root-level `timestamp`** key. PlotJuggler receives the data and sees the signal names, but cannot assign time values to them, so nothing plots.

## Fix

Add `timestamp` to `RobotData.asdict()` output at the root level.

In `[humanoid-gym/humanoid/envs/base/robot_data.py](humanoid-gym/humanoid/envs/base/robot_data.py)`, modify `RobotData`:

```python
@dataclass
class RobotData:
    timestamp: float          # <-- ADD this field
    state: RobotState
    control_input: ControlInput
    control_output: ControlOutput
    learning: LearningData
```

And in `__init__`:

```python
def __init__(self, timestamp, env, actions=None):
    timestamp += 1000000.0
    self.timestamp = timestamp    # <-- ADD this line
    self.state = RobotState(timestamp, env)
    ...
```

This ensures `asdict()` produces `{"timestamp": ..., "state": {...}, ...}` with the timestamp at root level, exactly as PlotJuggler expects.

## Verification steps

1. Edit `robot_data.py` on local machine
2. `scp` the updated file to the remote host (container bind-mounts the host directory)
3. Re-run the launcher
4. Start UDP streamer in PlotJuggler (port 9870, JSON)
5. Confirm curves populate in the panels within seconds of streaming start
6. Capture PlotJuggler log to verify no crash
