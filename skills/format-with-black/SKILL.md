---
name: format-with-black
description: Format Python code with Black (the uncompromising formatter). Use when the user asks to format code, to run Black, to blacken code, or when discussing Python code style or formatting.
---

# Format with Black

## When to apply

- User requests formatting, Black, or Python code style
- User says "run Black," "blacken," or "format with Black"
- When suggesting or editing Python and formatting matters

## Quick start

1. **Default**: Run from repo root: `black .`
2. **Subset**: Run on a path: `black <path>` (e.g. `black src/`)
3. **Project config**: If `pyproject.toml` or `[tool.black]` exists, Black uses it (line-length, include/exclude, etc.). Do not duplicate options in the skill.

## Optional flags

- `--check`: Only check; do not write (e.g. CI)
- `--diff`: Show diff instead of writing

Use only when relevant to the request.

## Black not installed

- Recommend: `pip install black` or add Black to dev-dependencies
- Do not assume a specific env manager (venv, poetry, etc.)

## No config found

If the project has no Black config, running `black .` or `black <path>` uses Black’s defaults. Do not create or modify project-specific Black config (e.g. `pyproject.toml`) unless the user explicitly asks.
