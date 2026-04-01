# Clean Up Orphans

Review and kill orphaned terminal processes from previous agent sessions.

Invoke as `/clean-up-orphans`.

## Workflow

1. **Scan terminal files.** Read all files in the terminals folder (the path is provided in the system context for each workspace). Identify active processes: those with `running_for_ms` in the header and no `exit_code` in the footer. Record PID, last command, working directory, and running duration for each.

2. **Scan listening ports.** Run:
   ```
   lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null
   ```
   Filter out system and IDE processes by name (e.g., `Cursor`, `Cursor Helper`, `controlCenter`, `rapportd`, `sharingd`, and similar IDE/OS services). Note any remaining listeners not already captured by step 1.

3. **Present a grouped summary.** Format:
   ```
   Active terminal processes:
     - Terminal <id>: `<command>` (running <duration>) — PID <pid>
     ...

   Listening ports (not in tracked terminals):
     - PID <pid>: `<process>` on port <port>
     ...
   ```
   Mark anything running longer than 1 hour as `(likely stale)`.

4. **Propose a kill list.** Recommend killing processes that appear stale or orphaned. Do NOT recommend killing processes that look intentionally user-started (e.g., an explicitly requested dev server in a recent conversation).

5. **Wait for approval.** Ask the user once:
   > "Kill the recommended processes? Reply `yes`, `all`, or specify exceptions."

6. **Execute.** For each approved process:
   - Run `kill <pid>`.
   - Wait 3 seconds, then check if the process is still alive with `kill -0 <pid> 2>/dev/null`.
   - If still alive, escalate with `kill -9 <pid>`.
   - Report each result: killed, already dead, or failed.

## Guardrails

- Never kill without user approval.
- Never kill Cursor's own processes, IDE internals, or system services.
- If no active processes are found, report "No orphaned processes found" and stop.
