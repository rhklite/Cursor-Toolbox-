---
name: Feishu Export Rule
overview: Create a Cursor rule that auto-prepends a Feishu conversion prompt when the agent translates markdown to Chinese or exports for Feishu.
todos:
  - id: create-rule
    content: Create `.cursor/rules/feishu-export-prompt.mdc` with frontmatter and rule body
    status: completed
  - id: sync-toolbox
    content: Commit, push, and run sync workflow for the new rule
    status: completed
isProject: false
---

# Feishu Export Prompt Rule

## What

Create a file-scoped Cursor rule at `[.cursor/rules/feishu-export-prompt.mdc](.cursor/rules/feishu-export-prompt.mdc)` that triggers when markdown files are open and the user asks to translate to Chinese or export for Feishu.

## Rule Behavior

When the agent detects either condition:

- User asks to **translate / convert a markdown document to Chinese**
- User mentions **Feishu** (飞书) or **exporting for Feishu**

The agent must prepend the following line at the very top of the exported output:

```
将以下的Markdown文档转为飞书文档形式，并且保证所有的Markdown元素可以被正确地渲染。
```

## Rule File

- **Path:** `.cursor/rules/feishu-export-prompt.mdc`
- **Frontmatter:** `globs: **/*.md`, `alwaysApply: false`
- Content will list the two trigger conditions, the exact prompt text, and placement (first line of output).

## Sync

After creating the rule, run the toolbox sync workflow per the `sync-toolbox-after-toolbox-edits` rule.
