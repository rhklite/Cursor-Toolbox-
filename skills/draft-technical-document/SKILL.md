---
name: draft-technical-document
description: Drafts technical documents following concise, table-first, audience-layered conventions. Use when the user asks to draft, write, or create a technical document, design document, specification, or evaluation framework.
---

# Draft Technical Document

## Role

Produces technical documents that are scannable by decision makers and detailed enough for engineers, using tables over prose and minimal redundancy.

## Parameters

**Verbosity** (set by user or default):

- **moderate** (default) — brief paragraphs where needed, tables for structured data, 2-3 sentence rationale per design decision
- **terse** — one sentence per idea, tables only, no paragraph blocks

If the user specifies a verbosity level, use it. Otherwise default to moderate.

## Abstract Requirements

The Abstract is mandatory in every document. It gives the reader an at-a-glance understanding of what was done. Five sub-principles govern it:

1. **Always present** — Every document must have an Abstract section. No exceptions.

2. **Context block first** — Opens with a bold subheading (name is flexible: "Working Condition", "Purpose", "Scope", etc.) and 1-2 sentences establishing the system/subject and its operating conditions.

3. **Core deliverable stated** — The abstract must state the document's central outcome:
   - Evaluation docs: pass/fail criterion or success definition
   - Design docs: what was built and why
   - Handoff docs: scope of the handoff and current status

4. **Key outputs as table** — The most important outputs appear as a compact table in the abstract:
   - Evaluation docs: key metrics with targets
   - Design docs: key files, classes, or artifacts
   - Handoff docs: deliverables and status

5. **Hybrid depth rule** — Tables can appear in compact form in the abstract even if expanded in a later section. Prose must not be repeated.

## General Principles

These are hard requirements. Every draft must satisfy all seven.

1. **Tables over prose** — Structured data (criteria, metrics, thresholds, comparisons, tier breakdowns) goes in tables, never inline paragraphs.

2. **Bold table titles** — Every table gets a bold title on the line directly above it. No introductory paragraph between the title and the table.

3. **Subheadings as anchors** — Sections with multiple conceptual blocks get bold subheadings to give readers scan points. Do not let a section run as a single unbroken wall of text.

4. **One sentence per idea** — Design rationale entries state what was decided and why in 1-2 sentences. No motivation paragraphs, no elaboration.

5. **No implied content** — If the reader will observe something themselves (e.g., a graphic has a legend), do not describe it in the document. Only state what the reader cannot infer.

6. **Operational notes are prominent** — Notes about automation, generation, scope, or audience go immediately under the section title (use a blockquote), not buried at the end.

7. **Audience layering** — The document has two reading depths:
   - Top level (Abstract, summaries, criterion definitions): readable by a decision maker with no technical deep-dive
   - Detail level (metric breakdowns, diagnostics, design decisions): for the engineer

## Redundancy policy

Avoid creating redundant sections. If information appears in one place, do not repeat it in another. If a section would only restate what the reader already has, omit it entirely.

## Recommended Template

Use as starting scaffolding. Adapt headings to fit the document's subject.

```markdown
# [Document Title]

**[Metadata key]:** [value]
**[Metadata key]:** [value]

---

## Abstract

**[Context Subheading]**

[1-2 sentence context. Then the key pass/fail or success criterion inline.]

**[Criterion / Gates Title]**

| Column | Column |
|--------|--------|
| ...    | ...    |

**[Key Metrics Title]**

| Column | Column | Column |
|--------|--------|--------|
| ...    | ...    | ...    |

---

## [Core Definition Section]

[Formal definition of the central criterion, with detailed table.]

[1-2 sentence design rationale for why this definition was chosen.]

---

## [Breakdown Section]

### [Subsection]

| ... | ... |
|-----|-----|

### [Subsection]

| ... | ... |
|-----|-----|

---

## [Design / Process Section]

### [Sequence or Workflow]

[Diagram or sequence if applicable.]

[1-2 sentence explanation of what happens.]

---

### Design Decisions

#### [Decision Title]

[1-2 sentences: what and why.]

#### [Decision Title]

[1-2 sentences: what and why.]

---

### [Output / Reporting Section]

> [Operational note about how this output is generated.]

[Structure description with table if applicable.]

---

*[Closing scope note.]*
```

## Workflow

1. Gather the subject, scope, and audience from the user (or infer from context).
2. Ask for verbosity preference if not specified. Default to moderate.
3. Draft the document using the template scaffolding and all seven principles.
4. After the draft is complete, ask: "Generate a Chinese translation (.zh.md)?"
   - If yes, read and follow `~/.cursor/skills/translate-to-chinese/SKILL.md`. This is mandatory -- do not translate inline without reading the skill first, as it contains a hard requirement for the rendering prompt.
   - If no, skip.
