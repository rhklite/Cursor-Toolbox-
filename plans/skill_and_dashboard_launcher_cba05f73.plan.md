---
name: Skill and Dashboard Launcher
overview: Create a Cursor skill for the policy lineage tracker agent contract and a clickable macOS launcher for the dashboard server.
todos:
  - id: create-skill
    content: Create ~/.cursor/skills/policy-lineage-tracker/SKILL.md with agent contract instructions, intent schema, and action examples
    status: completed
  - id: fix-contract-paths
    content: Update cursor_agent_contract.md to use macOS paths instead of Linux paths
    status: completed
  - id: create-launcher
    content: Create 'Launch Dashboard.command' clickable executable and chmod +x it
    status: completed
isProject: false
---

# Skill and Dashboard Launcher

## 1. Cursor Skill for Agent Contract

A **skill** (not a rule or command) is the right fit here because the agent contract describes a specialized multi-step workflow with domain-specific knowledge: parsing natural-language requests into structured JSON intents, calling `tracker_cli.py apply-intent`, and confirming results. This goes beyond what a simple rule or command can express.

**Location:** `~/.cursor/skills/policy-lineage-tracker/SKILL.md` (personal skill, available across all projects)

The skill will:

- Trigger when the user mentions policy lineage, experiment tracking, mutations, runs, tasks, or the tracker
- Instruct the agent to parse NL into a structured intent JSON object
- Provide the intent schema and compact action examples (from `[cursor_agent_contract.md](cursor_agent_contract.md)`)
- Use the correct macOS executable path: `/Users/HanHu/software/policy-lineage-tracker/tracker_cli.py`
- Reference `[SCHEMA.md](SCHEMA.md)` for detailed graph model docs (progressive disclosure)

## 2. Fix Hardcoded Linux Path in Contract

`[cursor_agent_contract.md](cursor_agent_contract.md)` references `/home/huh/software/Han Hu Software/policy-lineage-tracker/` (a Linux path). Update both executable paths to the macOS workspace path `/Users/HanHu/software/policy-lineage-tracker/`.

## 3. Clickable Dashboard Launcher (`.command` file)

On macOS, a `.command` file is a double-clickable shell script that opens in Terminal automatically.

**Location:** `/Users/HanHu/software/policy-lineage-tracker/Launch Dashboard.command`

The script will:

- `cd` to the project directory
- Start `dashboard_server.py` on port 8765
- Wait briefly for the server to bind, then `open http://127.0.0.1:8765` to launch the browser
- Keep Terminal open so the user can see server output and Ctrl+C to stop
- Make the file executable (`chmod +x`)

