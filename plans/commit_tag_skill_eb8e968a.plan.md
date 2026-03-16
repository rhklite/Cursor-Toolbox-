---
name: commit tag skill
overview: Create a personal Cursor skill that formats commit messages as `<type> Message` using a common set of commit-type tags.
todos:
  - id: create-dir
    content: Create personal skill directory at ~/.cursor/skills/commit-tag-prefix/
    status: completed
  - id: author-skill
    content: Write SKILL.md with metadata, format rule, tag set, examples, and validation checklist
    status: completed
  - id: verify-skill
    content: Validate format consistency and discovery-oriented description
    status: completed
isProject: false
---

# Commit Tag Prefix Skill Plan

## Goal

Create a personal skill that automatically guides commit-message generation to use the format `<type> Commit message`, where `type` is a short commit category.

## Files to Create

- `[/home/huh/.cursor/skills/commit-tag-prefix/SKILL.md](/home/huh/.cursor/skills/commit-tag-prefix/SKILL.md)`

## Implementation Steps

- Add a new personal skill directory named `commit-tag-prefix` under `~/.cursor/skills/`.
- Write `SKILL.md` with valid frontmatter:
  - `name: commit-tag-prefix`
  - `description`: explicitly states WHAT it does (prefixes commit messages with angle-bracketed type tags) and WHEN to use it (when user asks to commit, write commit messages, or prepare commit text).
- In the skill instructions, enforce message format: `<type> Commit message`.
- Define the default tag set as requested: `feature`, `bug-fix`, `docs`, `refactor`, `test`, `chore`.
- Add a short selection guide (how to choose the correct type from the change intent) and concise examples.
- Add a validation checklist in the skill so the agent verifies the final message begins with `<type>` before committing.

## Verification

- Confirm `SKILL.md` is concise and under 500 lines.
- Confirm terminology is consistent (`type`, `tag`, `commit message`) and examples match the exact format `<type> Message`.
- Confirm the description includes trigger terms to improve automatic skill activation (commit, commit message, staged changes, git commit).
