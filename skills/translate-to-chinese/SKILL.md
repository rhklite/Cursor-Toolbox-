---
name: translate-to-chinese
description: Translates Markdown documents to Chinese while preserving all rendering elements. Use when the user asks to translate a document to Chinese, create a Chinese version, or generate a .zh.md file.
---

# Translate to Chinese

## Hard Requirement

Every translated Chinese Markdown document MUST begin with the following prompt as an HTML comment on the very first line, before any other content:

```
<!-- 以下是一个Markdown file，我把它转成中文文件，并且保证里面所有的元素可以被正确渲染。包括但不仅限于表格、图表，代码。 -->
```

This is non-negotiable. Never omit it.

## Workflow

1. Read the source English document.
2. Create or overwrite the target file (same name with `.zh.md` suffix).
3. Insert the HTML comment prompt on line 1.
4. Translate all prose to Chinese. Preserve:
   - Markdown structure (headings, lists, blockquotes, horizontal rules)
   - Tables (translate cell content, keep pipe formatting)
   - Mermaid diagrams (translate labels and notes inside the code fence)
   - Code blocks (do not translate code; translate comments only)
   - Bold, italic, and link formatting
   - Frontmatter fields (do not translate keys; translate values only if prose)
5. Keep technical terms in their original form where a Chinese equivalent would be ambiguous (e.g., PD snap, T_fail, CoM).
6. Verify the output renders correctly by checking table column counts and mermaid syntax.
