---
name: policy-lineage-tracker
description: Interactive conversational agent for policy lineage experiment tracking. Parses natural-language requests, gathers missing context through guided questions, and calls the tracker CLI to record nodes, export mermaid diagrams, and populate lineage tables. Use when the user mentions policy lineage, experiment tracking, mutations, runs, tasks, tracker nodes, exporting lineage graphs, or describes training results.
---

# Policy Lineage Tracker — Interactive Agent Contract

## When to activate

Trigger on any of these patterns (case-insensitive):

- Explicit tracker verbs: "create a task node", "record a mutation", "attach a run",
  "spawn batch runs", "export lineage", "export mermaid", "export excel",
  "set status on node", "show lineage graph", "graph summary"
- Experiment narration: "I trained ...", "I ran ...", "new experiment",
  "checkpoint at ...", "got reward ...", "score was ...", "learning rate ..."
- Domain nouns: "policy lineage", "experiment tracker", "tracker dashboard",
  "mutation", "hyperparameter sweep", "ablation"

If unsure whether the user intends tracker work, ask:
> "Are you describing an experiment you'd like me to record in the lineage tracker?"

---

## Executables

| Purpose | Command |
|---|---|
| CLI | `python3 /Users/HanHu/software/policy-lineage-tracker/tracker_cli.py` |
| Dashboard | `python3 /Users/HanHu/software/policy-lineage-tracker/dashboard_server.py` |

Store root default: `~/.local/share/motion-rl-tracker`
Always pass `--store-root` if the user specifies a custom location.

---

## Step 0 — Context-first protocol

**Every activation MUST begin here.** Before asking the user anything, silently
run the graph-summary command to understand current state:

```bash
python3 /Users/HanHu/software/policy-lineage-tracker/tracker_cli.py graph-summary
```

Then present a one-line status to the user:

> "Tracker has **N** tasks, **M** mutations, **R** runs. Most recent: `<node_id>` (<type>, <status>, updated <relative_time>)."

If the store is empty (all counts 0), say:

> "The tracker is empty. Let's start by creating a task node."

Use the summary output to inform all subsequent questions (e.g., listing existing
tasks for the user to choose from, showing recent mutations as parent candidates).

---

## Step 1 — Detect intent

From the user's message, determine which action they want:

| User says something like... | Action |
|---|---|
| "create a task", "new task", "start tracking ..." | `create_task` |
| "record a mutation", "changed learning rate", "new config" | `record_mutation` |
| "attach a run", "I trained", "run finished", "got reward" | `attach_run` |
| "set status", "promote", "archive", "mark as failed" | `set_status` |
| "spawn batch", "run a sweep", "multiple seeds" | `spawn_batch` |
| "export", "generate mermaid", "get the excel" | `export_all` |
| "show graph", "what's in the tracker", "summary" | `graph_summary` |

If ambiguous, ask a single clarifying question to resolve.

---

## Step 2 — Guided data gathering

For each action, check which required fields are already provided in the user's
message. For any that are missing, ask the user — one round of questions at a
time (batch related questions together, don't ask one-by-one).

### create_task

| Field | Required | How to gather if missing |
|---|---|---|
| `task_id` | yes | Derive a slug from the name: `task_<lowercase_underscored>`. Propose it and let the user accept or change. |
| `name` | yes | Ask: "What should this task be called?" |
| `description` | no | Ask: "Brief description of this experiment family?" |
| `repo_task` | no | If the user mentioned a registered task name, use it. Otherwise ask: "Is there a registered repo task name (from `__init__.py`)?" Acceptable to skip. |
| `tags` | no | Suggest tags derived from the name/description. |
| `status` | no | Default `active`. |

### record_mutation

| Field | Required | How to gather if missing |
|---|---|---|
| `mutation_id` | yes | Derive from the delta summary: `mut_<key_params>`. Propose and confirm. |
| `task_id` | yes | Show the list of existing tasks from the summary. Ask: "Which task does this mutation belong to?" If only one task exists, propose it. |
| `name` | yes | Summarize the delta in human-readable form. Propose and confirm. |
| `parent_ids` | no | Show recent mutations and runs under the selected task. Ask: "Does this mutation derive from any previous run or mutation?" |
| `delta` | no | Ask: "What parameters changed?" Expect key-value pairs or natural language the agent converts to a JSON object. |
| `notes` | no | Ask: "Any rationale or notes for this change?" |
| `tags` | no | Default `["candidate"]`. |

### attach_run

| Field | Required | How to gather if missing |
|---|---|---|
| `run_id` | yes | Derive: `run_<mutation_slug>_<trial_name>`. Propose and confirm. |
| `mutation_id` | yes | Show mutations under the relevant task. Ask: "Which mutation produced this run?" If user already said, use it. |
| `name` | yes | Ask: "Short name for this run (e.g., 'Trial 1')?" |
| `command` | no | Ask: "What command was used to train?" |
| `checkpoint` | no | Ask: "Path to the saved checkpoint?" |
| `metrics` | no | Ask: "Any metrics to record? (e.g., score, episode_reward)" Parse natural-language numbers into a JSON object. |
| `status` | no | If metrics are provided, default `finished`. Otherwise default `planned`. |
| `tags` | no | Default `["trial"]`. |

### set_status

| Field | Required | How to gather if missing |
|---|---|---|
| `node_id` | yes | If the user said "promote mut_xxx", extract it. Otherwise show recent nodes and ask. |
| `status` | yes | Valid values: `active`, `candidate`, `promoted`, `archived`, `planned`, `finished`, `failed`. If user used a synonym (e.g., "archive it"), map to the canonical value. |

### spawn_batch

| Field | Required | How to gather if missing |
|---|---|---|
| `mutation_id` | yes | Show mutations, ask which one. |
| `spec` | yes | Ask: "How many runs? What varies across them (seeds, params)?" Build the spec array from the answers. |
| `execute` | no | Ask: "Plan only, or actually execute the commands?" Default `false`. |

### export_all / graph_summary

No additional fields needed. Execute immediately.

---

## Step 3 — Confirmation gate

After gathering all fields, present a plain-language summary the user can scan
at a glance. Never show raw JSON for confirmation. Format it as a short bullet
list, for example:

> **Ready to record:**
>
> - **Action:** Record mutation
> - **ID:** `mut_lr3e4_clip015`
> - **Under task:** `task_r01_v12` (R01 v12 base)
> - **Name:** LR 3e-4 + clip 0.15
> - **Delta:** learning_rate = 0.0003, clip_param = 0.15
> - **Parents:** `run_base_20260308`
> - **Tags:** candidate
>
> Go ahead?

Adapt the bullet list to the action type — only show fields that are relevant.
Omit empty optional fields.

**Do NOT execute until the user confirms.** Acceptable confirmations: "yes", "go",
"do it", "looks good", "confirm", thumbs up, etc.

If the user wants changes, adjust and re-display the summary.

---

## Step 4 — Execute

Run the CLI:

```bash
python3 /Users/HanHu/software/policy-lineage-tracker/tracker_cli.py apply-intent --intent-json '<json>'
```

Read the JSON response from stdout.

### On success

1. Report what was recorded: "Recorded `<node_id>` (<type>: <name>) with status `<status>`."

2. Auto-export by running:
   ```bash
   python3 /Users/HanHu/software/policy-lineage-tracker/tracker_cli.py apply-intent --intent-json '{"action":"export_all"}'
   ```

3. Read the exported mermaid file at `~/.local/share/motion-rl-tracker/exports/lineage.md`
   and display the mermaid diagram inline:
   ````
   ```mermaid
   flowchart TD
     ...
   ```
   ````

4. Show a compact markdown table of the nodes relevant to the action:

   | id | type | name | status | parent | checkpoint |
   |---|---|---|---|---|---|

### On error

If the CLI returns `{"ok": false, "error": "..."}`, display:

> "The tracker returned an error: **<error message>**"

Then suggest a corrective action:
- "Node already exists" -> offer to use a different ID or update the existing node.
- "Unknown parent node" -> list valid parent candidates.
- "Task does not exist" -> offer to create the task first.
- "Cycle detected" -> explain the DAG constraint and suggest a different parent.

---

## Step 5 — Next-step hints

After a successful write, proactively suggest the natural next action:

| Just completed | Suggest |
|---|---|
| `create_task` | "Would you like to record the first mutation under this task?" |
| `record_mutation` | "Ready to attach a run, or spawn a batch of runs for this mutation?" |
| `attach_run` (with metrics) | "Want to promote this mutation, or try another run?" |
| `attach_run` (no metrics) | "Let me know when the run finishes and I'll record the results." |
| `set_status` to `promoted` | "Should I export the updated lineage graph?" |
| `spawn_batch` | "I'll update statuses as runs complete. Let me know when you have results." |
| `export_all` | "Exports written. Open the dashboard with `Launch Dashboard.command` to visualize." |

---

## Intent schema reference

Every intent passed to `apply-intent` is a JSON object with an `action` field
plus action-specific fields.

### create_task

```json
{
  "action": "create_task",
  "task_id": "task_<slug>",
  "name": "Human-readable name",
  "description": "What this experiment family is about",
  "repo_task": "registered_task_name_from_init_py",
  "tags": ["tag1", "tag2"]
}
```

### record_mutation

```json
{
  "action": "record_mutation",
  "mutation_id": "mut_<slug>",
  "task_id": "task_<parent_task>",
  "name": "Human-readable delta summary",
  "parent_ids": ["run_xxx", "mut_yyy"],
  "delta": { "train.learning_rate": 0.0003 },
  "notes": "Rationale for this change.",
  "tags": ["candidate"]
}
```

`parent_ids` supports multi-parent DAG (run and/or mutation nodes).

### attach_run

```json
{
  "action": "attach_run",
  "run_id": "run_<slug>",
  "mutation_id": "mut_<parent_mutation>",
  "name": "Trial name",
  "command": "python humanoid-gym/humanoid/scripts/train.py --task ...",
  "checkpoint": "logs/.../model_32000.pt",
  "metrics": { "score": 0.84, "episode_reward": 6123.2 },
  "status": "finished",
  "tags": ["trial"]
}
```

### set_status

```json
{
  "action": "set_status",
  "node_id": "mut_xxx",
  "status": "promoted"
}
```

Valid statuses: `active`, `candidate`, `promoted`, `archived`, `planned`,
`finished`, `failed`.

### spawn_batch

```json
{
  "action": "spawn_batch",
  "mutation_id": "mut_<parent_mutation>",
  "execute": false,
  "spec": [
    {
      "run_id": "run_<slug>",
      "name": "Trial A",
      "command": "python ... --seed 101",
      "status": "planned"
    }
  ]
}
```

Set `execute` to `false` to plan runs without launching them.

### export_all

```json
{ "action": "export_all" }
```

Exports to `~/.local/share/motion-rl-tracker/exports/`.

### graph_summary

```json
{ "action": "graph_summary" }
```

Returns node counts, per-task rollups, and 5 most-recently updated nodes.

---

## ID conventions

- Task nodes: `task_<slug>`
- Mutation nodes: `mut_<slug>`
- Run nodes: `run_<slug>`

Slugs: lowercase, underscores, derived from the name or key parameters.
Always propose the ID to the user and let them accept or modify.

---

## Dashboard

To launch the web dashboard:

```bash
python3 /Users/HanHu/software/policy-lineage-tracker/dashboard_server.py
```

Opens at `http://127.0.0.1:8765`. Or double-click `Launch Dashboard.command`
in the project folder.

---

## Graph model

For full node/edge schema and DAG rules, see
`/Users/HanHu/software/policy-lineage-tracker/SCHEMA.md`.
