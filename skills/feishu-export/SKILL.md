---
name: feishu-export
description: >-
  Exports a markdown document to Feishu as a cloud doc and writes the returned
  URL into the docs table of contents. Use when the user says "export to Feishu",
  "publish to Feishu", "upload to Feishu", "push to 飞书", "导出飞书", or
  "send to Feishu".
---

# Feishu Export

## Role

Exports a markdown document to Feishu via the docx_builtin_import MCP tool,
then records the Feishu URL in the docs table of contents.

## Steps

### 1. Identify the source document

Determine which document to export:
- If the user specifies a file path, use it directly.
- If the user has a file open in the editor, confirm it with the user.
- If ambiguous, ask the user to specify.

### 2. Read and prepare content

- Read the full markdown content of the source document.
- The content is exported as-is. If the user wants a Chinese translation,
  they should run the en-to-zh-translation skill first and export the
  translated version.

### 3. Export to Feishu

Call the Feishu MCP tool:
- Server: `user-feishu-mcp`
- Tool: `docx_builtin_import`
- Arguments:
  - `file_name`: the document filename (without path or extension)
  - `markdown`: the full markdown content

Capture the returned Feishu document URL from the response.

### 4. Update the table of contents

Open `docs/tableofcontent.md` in the workspace root. Find the line that references
the exported document. Append the Feishu link to that line using the format:

```
- [filename](relative/path/to/file.md) — Document Title | [飞书](https://feishu-url)
```

If the document does not yet appear in the TOC, run `bash docs/update-toc.sh`
first to regenerate it, then add the Feishu link.

### 5. Confirm

Report to the user:
- The Feishu URL
- That the TOC has been updated with the link
