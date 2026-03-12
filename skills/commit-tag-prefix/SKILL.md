---
name: commit-tag-prefix
description: Prepends git commit messages with an angle-bracketed type tag and enforces a consistent format. Use when creating commit messages, preparing git commit text, or when the user asks to commit staged changes.
---

# Commit Tag Prefix

## Purpose

Generate commit messages in this required format:

`<type> Commit message`

## When To Apply

Apply this skill when:
- The user asks to commit changes.
- The user asks for a commit message.
- The workflow includes reviewing staged changes and preparing `git commit`.

## Allowed Types (Default Set)

Use one of these tags:
- `feature`
- `bug-fix`
- `docs`
- `refactor`
- `test`
- `chore`

## Type Selection Guide

- Use `feature` for new behavior, capabilities, or user-facing functionality.
- Use `bug-fix` for correcting incorrect behavior or regressions.
- Use `docs` for documentation-only updates.
- Use `refactor` for internal code restructuring without behavior changes.
- Use `test` for adding or improving tests.
- Use `chore` for maintenance work (tooling, configs, housekeeping) that is not feature or bug-fix work.

## Message Construction Rules

1. Start with a valid type tag in angle brackets.
2. Add a single space after the closing bracket.
3. Write a concise, sentence-style summary of intent.
4. Do not add a colon after the tag.

## Examples

- `<feature> Add configurable reward shaping for jump landing`
- `<bug-fix> Correct foot contact detection on uneven terrain`
- `<docs> Document training flags for full-state observations`
- `<refactor> Simplify action clipping logic in legged robot`
- `<test> Add regression test for observation normalization`
- `<chore> Update pre-commit hooks for lint consistency`

## Validation Checklist

Before finalizing a commit message, verify:
- [ ] Message starts with `<type> `.
- [ ] `type` is one of: `feature`, `bug-fix`, `docs`, `refactor`, `test`, `chore`.
- [ ] No colon after the tag (use `<type> Message`, not `<type>: Message`).
- [ ] The summary is clear and specific to the change intent.
