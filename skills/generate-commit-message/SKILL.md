---
name: generate-commit-message
description: Generate commit messages with ⟨tag⟩ prefix by analyzing git diff. Use when the user asks for a commit message, git commit help, staged changes summary, or wants to commit.
---

# Generate Commit Message

## Instructions

1. **Infer changes**: Run `git diff --staged` (or `git status` if nothing staged) to see what changed.
2. **Pick a tag**: Choose the single best-matching tag from the table below.
3. **Format**: `⟨tag⟩ Imperative summary` — first line under ~72 chars.
4. **Body** (optional): Add blank line, then details if the commit warrants explanation.

## Tag reference

| Tag | Use when |
| --- | --- |
| ⟨feat⟩ | New feature or capability |
| ⟨fix⟩ | Bug fix |
| ⟨docs⟩ | Documentation only (README, comments, etc.) |
| ⟨style⟩ | Formatting, whitespace, no logic change |
| ⟨refactor⟩ | Code restructure, neither fix nor feature |
| ⟨perf⟩ | Performance improvement |
| ⟨test⟩ | Adding or fixing tests |
| ⟨build⟩ | Build system, dependencies, tooling |
| ⟨ci⟩ | CI config or scripts |
| ⟨chore⟩ | Other maintenance (cleanup, config, etc.) |
| ⟨revert⟩ | Reverting a previous commit |

## Conventions

- **Imperative mood**: "Add" not "Added", "Fix" not "Fixed"
- **First line**: `⟨tag⟩ Short summary` (under ~72 chars)
- **Body** (optional): Blank line, then details if needed for complex commits

## Examples

**Input** (diff: new `login()` function in auth.py)
```
Output: ⟨feat⟩ Add login endpoint to auth module
```

**Input** (diff: corrected date formatting in reports)
```
Output: ⟨fix⟩ Correct date formatting in report generation
```

**Input** (diff: README updates, no code changes)
```
Output: ⟨docs⟩ Update README with setup instructions
```
