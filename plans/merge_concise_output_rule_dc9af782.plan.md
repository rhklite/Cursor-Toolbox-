---
name: Merge concise output rule
overview: Merge a structured user-facing output format (motivation, change, expected outcome) into the existing `concise-agent-summaries.mdc` rule, covering plans, summaries, and mid-task updates without affecting internal reasoning.
todos:
  - id: merge-rule
    content: Rewrite concise-agent-summaries.mdc with the merged structured output template
    status: completed
isProject: false
---

# Merge Structured Output Format into concise-agent-summaries.mdc

## Target file

[.cursor/rules/concise-agent-summaries.mdc](/Users/HanHu/.cursor/rules/concise-agent-summaries.mdc) — `alwaysApply: true`, merged rule.

## What changes

Rewrite the rule to add a **structured output template** for all user-visible output (plans, summaries, mid-task updates). Internal thinking, critic loops, and tool calls are explicitly excluded.

### Proposed merged rule content

```markdown
---
description: Enforce structured, scannable output for all user-visible plans, summaries, and updates
alwaysApply: true
---

# Concise Structured Output

Applies to every user-visible message: plans, summaries, and mid-task updates.
Does NOT apply to internal reasoning, critic loops, or tool-call arguments.

## Output template

Use this skeleton for any plan, summary, or status update:

- **Why**: 1-sentence motivation or problem statement. Use "issue" for fixes, "goal" for features/refactors.
- **What**: The logical change(s) — what is being added, removed, or modified. Not file paths alone; describe the behavior delta.
- **Where** (optional, include when more than 1 file): Files or modules touched, as a compact list.
- **Outcome**: Expected behavior after the change. Include breaking changes or verification steps if any.

## Formatting rules

- Lead with the direct outcome when answering a completed-task question.
- Cap bullets at 3 per section; link to details if more are needed.
- No narrative paragraphs, hype, or softening language.
- Never use anchor brackets (e.g. `<tag>`, `<example>`) in user-visible output text. Use plain markdown formatting instead.
- For single-line trivial changes, collapse into one sentence covering Why + What + Outcome.
- For multi-scope changes (5+ files or 3+ logical changes), group by logical concern with sub-bullets.

## Question responses

- Start with lowercase `yes` or `no` as the first token.
- Keep explanation to one short sentence after the token.

## Task completion

- End with standalone `done` or `not doable`.
- `done` only if completed this turn.
- `not doable` when blocked by environment, permissions, or constraints.
```

### Key differences from current rule

- **Added**: Structured 4-field template (Why / What / Where / Outcome).
- **Added**: Scaling guidance — collapse trivial changes, group large ones.
- **Added**: Explicit scope exclusion for internal reasoning.
- **Preserved**: `yes`/`no` response format and `done`/`not doable` tokens.
- **Removed**: Generic "final result / key evidence / next action" ordering (replaced by the more specific template).

### Edge-case mitigations baked in

- "Why" uses "issue" or "goal" depending on context, avoiding forced "issue" for new features.
- "Where" is optional for single-file changes to avoid noise.
- "Outcome" explicitly calls for breaking changes and verification steps.
- Scaling rule: one-sentence collapse for trivial changes, grouped sub-bullets for large ones.
