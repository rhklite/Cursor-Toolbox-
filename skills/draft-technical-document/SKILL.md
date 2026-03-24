---
name: draft-technical-document
description: Drafts technical documents following concise, table-first, audience-layered conventions. Use when the user asks to draft, write, or create a technical document, design document, specification, or evaluation framework.
---

# Draft Technical Document

## Role

Produces technical documents that are scannable by decision makers and detailed enough for engineers, using tables over prose and minimal redundancy.

## Parameters

**Verbosity** (set by user or default):

- **terse** (default) — one sentence per idea, tables only, no paragraph blocks
- **moderate** — brief paragraphs where needed, tables for structured data, 2-3 sentence rationale per design decision

If the user specifies a verbosity level, use it. Otherwise default to terse.

**Audience** (set by user or default):

- **decision makers and engineers** (default) — layered depth with executive scanability and implementation detail
- **custom audience** — follow the audience explicitly specified by the user

If the user specifies an audience, use it. Otherwise default to decision makers and engineers.

## Abstract Requirements

The Abstract is mandatory in every document. It gives the reader an at-a-glance understanding of what was done. Seven sub-principles govern it:

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

6. **No table-of-contents tables** — Do not include tables that index or summarize every section/topic of the document. PDF and other export formats generate their own TOC; a summary table that mirrors headings is redundant structure.

7. **Hypothesis handoff for design docs** — For design docs originating from thinking partner sessions, include a **Hypothesis** subsection in the abstract with top-level hypothesis, sub-hypotheses, and causal chain. Preserve this hypothesis as provided by the thinking partner output; do not generate or rewrite it.

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

## Hypothesis

### Top-level hypothesis

- [single sentence with expected outcome and success criterion]

### Sub-hypotheses

- [Sub-H1] [design decision] leads to [intermediate effect], supporting [top-level outcome].
- [Sub-H2] ...

### Causal chain

- [brief chain of how sub-hypotheses support the top-level]
- [supporting-not-conjunctive note]

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

## Output routing

All markdown files produced by this skill must be saved to `docs/design/published/` relative to the workspace root.

Rules:
- Write all markdown output to `docs/design/published/`.
- Create the directory if it does not exist (`mkdir -p docs/design/published`).
- After writing, run `bash docs/update-toc.sh` to refresh the table of contents.

## Workflow

1. Gather the subject and scope from the user (or infer from context).
2. Apply defaults when not specified: audience is decision makers and engineers; verbosity is terse.
3. Draft the document using the template scaffolding and all seven principles.
