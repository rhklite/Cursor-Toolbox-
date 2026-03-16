---
name: Reward doc readability refactor
overview: Refactor `docs/reward_design_analysis_sa_full_scenes.md` for readability and accuracy, updating Section 8 to match finalized design decisions, with 10 self-review cycles.
todos:
  - id: sections-1-3
    content: Shorten file map table, remove redundant mermaid graph in Section 3
    status: completed
  - id: section-4
    content: Extract formulas from table cells into compact lists below each sub-table
    status: completed
  - id: section-6
    content: Replace mermaid flowchart with grouped table, remove duplicate disturbance info
    status: completed
  - id: section-8-rewrite
    content: Update Section 8 tuning suggestions to match finalized design decisions
    status: completed
  - id: ten-review-cycles
    content: Run 10 self-review cycles (accuracy, redundancy, tables, formulas, flow, refs, grammar, consistency, balance, polish)
    status: completed
isProject: false
---

# Reward Design Doc Readability Refactor

Target: `[docs/reward_design_analysis_sa_full_scenes.md](docs/reward_design_analysis_sa_full_scenes.md)` (339 lines)

## Problems identified

- **Section 8 is stale**: Tuning suggestions conflict with finalized Design Decision v2 (rejected `ang_vel_xy`, kept `stand_still=0`, `amp_task_reward_lerp` is now 1.0, `stand_prob` reverted to 0.07). Must be updated.
- **Dense tables**: 4-5 column tables with long content are hard to scan on typical screen widths.
- **Redundant diagram**: Section 6.1 mermaid graph is a flat list styled as a flowchart — adds visual noise, not clarity.
- **Verbose prose**: Several paragraphs restate what the table already shows.
- **LaTeX in tables**: Formulas in table cells render poorly in many Markdown viewers; move to separate formula blocks or simplify.

## Changes by section

### Sections 1-2 (File Map, Config Inheritance)

- Shorten file paths in the table to relative basenames with links (no need for full paths twice).
- Keep the mermaid inheritance diagram as-is (it's useful and clean).

### Section 3 (Total Reward Architecture)

- Keep the blend formula and table. Remove the mermaid LR graph (the formula + table already communicate this; the graph adds nothing).

### Section 4 (Reward Terms)

- Split formula column out of the table into a compact formula list below each sub-table. Tables keep: Term, Scale, Brief description.
- Keep file links in tables but shorten to `filename#Lnnn`.

### Section 5 (Relative Importance Ranking)

- Keep the ranking table and pie charts as-is (they're clean).

### Section 6 (External Disturbances)

- Replace the mermaid flowchart with a grouped table (headers for "Every Step", "Each Reset", "Env Creation"). The flowchart is just a static list and the table below it duplicates the same information.
- Remove the duplicate information between the mermaid diagram and the table.

### Section 7 (Command Distribution)

- Keep as-is (already concise).

### Section 8 (Tuning Suggestions) — major rewrite

- **8.1**: Update the stabilization rewards table to reflect finalized decisions:
  - `stand_still`: keep at 0, note it may fight leg adaptation
  - `orientation`: deferred at 0.0, suggested -2.0 to -4.0 if needed
  - `ang_vel_xy`: explicitly rejected (cite design doc reason: 0.5-4.0/step during walking, competes with tracking)
  - `torso_ang_vel_xy_penalty`: updated to 0.03 (Stages 1-2), 0.05-0.10 (Stage 3)
  - `lin_vel_z`, `base_height`, `default_joint_pos`: deferred, show safe ranges
- **8.2**: `tracking_avg_lin_vel` stays at 2.0; `tracking_sigma_lin_vel` stays at 1.0 (both under active sweep testing)
- **8.3**: Remove `stand_prob` increase recommendation — the new episode structure (T_fail) guarantees standing exposure without changing command distribution
- **8.4**: Update push values to match stability priority config (0.65 m/s, 0.15 rad/s)
- **8.5**: `amp_task_reward_lerp = 1.0` is finalized — remove "0.3 to 0.5" suggestion
- **8.6**: Remove the "Recommended Starting Configuration" code block (superseded by the actual stability priority config)
- **8.7**: Update iterative tuning order to match design decision doc's three-stage curriculum approach

### Final pass

- Consistent heading style and numbering
- Remove orphaned notation sections
- Verify all file links still valid

## Review cycle approach

Each of the 10 review cycles will:

1. Re-read the current state of the document
2. Check one concern (accuracy, redundancy, table width, formula clarity, flow, cross-references, grammar, consistency, section balance, final polish)
3. Apply fixes for that concern

This produces focused, non-overlapping improvements rather than scattered edits.
