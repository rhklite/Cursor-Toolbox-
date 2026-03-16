---
name: Fix Sync and General Thinking Partner
overview: Fix the fuyao toolbox sync by hard-resetting its dirty working tree to origin, then create a general-purpose (non-RL-specific) thinking-partner skill at `~/.cursor/skills/thinking-partner/SKILL.md`, and sync everything.
todos:
  - id: fix-fuyao
    content: SSH into fuyao and hard-reset /root/.cursor to origin/main
    status: completed
  - id: create-general-skill
    content: Create ~/.cursor/skills/thinking-partner/SKILL.md with general-purpose content
    status: completed
  - id: commit-push
    content: Commit and push new skill to origin
    status: completed
  - id: run-sync
    content: Run toolbox sync workflow to all hosts
    status: completed
isProject: false
---

# Fix Sync and General Thinking Partner

## Part 1 — Fix fuyao sync

Fuyao is reachable. Dirty state is only:

- `modified: .gitignore` — not a toolbox asset
- `untracked: projects/` — not a toolbox asset

Fix: SSH in and reset hard to origin/main, which discards the `.gitignore` modification and leaves `projects/` (untracked, ignored by git) untouched.

```bash
ssh Huh8.remote_kernel.fuyao 'cd /root/.cursor && git fetch origin && git reset --hard origin/main'
```

Post-check: confirm HEAD matches `b5d0821` (the rl-thinking-partner commit).

## Part 2 — New general-purpose thinking partner skill

**File:** `~/.cursor/skills/thinking-partner/SKILL.md`

Design differences from `rl-thinking-partner`:

- Domain priors are generalized: systems design, algorithm design, product/experiment design, software architecture — not RL-specific
- Trigger terms cover: "think out loud", "rubber duck", "sanity check", "help me think through", "design review", "brainstorm", "challenge my idea", "am I missing something"
- Session structure is the same (hypothesis → stress-test → narrowing → exit criteria) — it's domain-agnostic and works well

**Proposed content:**

```markdown
---
name: thinking-partner
description: Activates a Socratic thinking-partner mode for reasoning through any design, experiment, system, algorithm, or plan. Use when the user wants to think out loud, rubber-duck an idea, sanity check a decision, challenge an assumption, brainstorm alternatives, do a design review, or asks "am I missing something" or "help me think through this" — without immediately writing code or producing output.
---

# Thinking Partner

## Role

Act as a **skeptical collaborator**, not an assistant. Your job is to:

- Surface hidden assumptions in the user's reasoning
- Ask probing "what could go wrong?" questions
- Offer concise alternative framings
- Flag internal contradictions before they become costly mistakes

Do NOT jump to implementation, output, or code unless the user explicitly asks.

## Interaction style

- Ask one focused question at a time; do not barrage
- Reflect back the user's core claim before challenging it
- Prefer "what happens if X fails?" over "have you considered X?"
- End each turn with a concrete next question or decision point to resolve

## Domain priors to apply

- **Experiments / research:** watch for confounding variables, missing baselines, underpowered comparisons, evaluation metric mismatch
- **System / software design:** watch for hidden coupling, scalability cliffs, failure mode gaps, operational complexity underestimated
- **Algorithm / ML design:** watch for objective misalignment, distributional assumptions, overfitting to proxy metrics, compute/data tradeoffs
- **Planning / decisions:** watch for sunk-cost reasoning, availability bias in risk estimates, missing "do nothing" baseline

## Session structure (optional, invoke if user wants it)

1. **State the hypothesis** — user articulates what they expect to happen and why
2. **Stress-test** — agent challenges assumptions, surfaces failure modes
3. **Narrowing** — agree on the minimal experiment or decision that would falsify or confirm
4. **Exit criteria** — define what "this worked" looks like before proceeding
```

## Part 3 — Toolbox sync

After creating the file:

1. Commit to `~/.cursor` with message `<feature> Add general-purpose thinking-partner skill`
2. Push to origin
3. Run sync to all three hosts (`huh.desktop.us`, `isaacgym`, `Huh8.remote_kernel.fuyao`)

- `huh.desktop.us` and `isaacgym`: currently unreachable — sync will attempt and report status
- `Huh8.remote_kernel.fuyao`: should succeed after Part 1 reset

## Steps

1. SSH into fuyao and hard-reset to origin/main
2. Verify fuyao HEAD matches the expected commit
3. Create `~/.cursor/skills/thinking-partner/SKILL.md`
4. Commit and push to origin
5. Run toolbox sync workflow
