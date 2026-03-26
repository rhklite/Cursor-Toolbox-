---
name: understand-document
description: Produces a structured comprehension artifact from an imported or attached document. Use when the user provides a document (PDF, markdown, spec, design doc) and says "help me understand", "explain this document", "summarize this document", "document comprehension", "read this for me", or "break this down for me". Only trigger on explicitly provided documents, not on general knowledge questions.
---

# Understand Document

## Role

Transform an imported document into a scannable comprehension artifact using a fixed 5-block structure. Optimized for engineering documents (system designs, specs, requirements, proposals) but applicable to any technical document.

## Intake

Before reading the document, ask the user one question:

> What is your reading goal for this document? (Press Enter to skip for generic comprehensive understanding.)

Record the response as **reader context**. If the user skips or provides no answer, default to: `generic: comprehensive understanding`.

Then read the source document in full.

## Output structure

Use the template at `~/.cursor/templates/understand-document-template.md` as scaffolding. Produce all 5 blocks below.

---

### Block 0 — Document Identity

No source metadata (no title, authors, date). Include only:

- **Scope** — one sentence: what system or problem the document covers
- **Thesis** — two bullets: (1) what the document claims, (2) what it proposes
- **Reader context** — the user's stated goal, or the default

---

### Block 1 — Why: Narrative and Motivation

Tell the story the document is written around. For process-centric documents (safety systems, protocols, pipelines) the motivation IS the primary flow. For documents where motivation and process are separable, include a brief **Background** subsection before the flow.

**Narrative flow** — numbered sequence, each step 1–2 sentences. Cover the full end-to-end scenario the document addresses.

**Branch points** — table of decision points within the flow.

| Condition | Outcome |
|-----------|---------|

**Trigger and terminal states** — what initiates the scenario and what the possible end states are (table or compact list).

---

### Block 2 — How: Architecture and Structure

**Components** — table of every named component in the document.

| Component | Role | Owner / Platform |
|-----------|------|-----------------|

**Data and control flows** — table of key message or signal paths.

| Source | Channel / Interface | Destination | Payload |
|--------|---------------------|-------------|---------|

**Key interfaces** — briefly note any communication mechanisms, protocols, or buses that govern the flows (1 sentence each).

---

### Block 3 — What Exactly: Requirements and Constraints

If the document is a spec or requirements document, extract hard constraints. If the document does not contain explicit requirements, note this and extract any implied constraints or thresholds instead.

**Per-component requirements** — table.

| Component | Requirement | Threshold / Constraint |
|-----------|-------------|----------------------|

**Timing and ordering constraints** — any sequencing, latency, or priority rules stated in the document.

**Stated success criteria** — what the document defines as correct operation or acceptable outcome.

---

### Block 4 — What's Unresolved: Gaps and Open Questions

**Underspecified areas** — things the document should define but does not.

**Internal contradictions** — any claims, requirements, or definitions that conflict with each other.

**Open questions for authors** — questions a reader would need answered to fully implement or evaluate the design.

If reader context was non-generic, add a final subsection:

**Gaps specific to reader's concern** — flag only the gaps and contradictions relevant to the user's stated reading goal.

---

## Stylistic rules

- Tables over prose for all structured data.
- Bold subheadings within each section.
- One sentence per idea. Terse always; no verbosity parameter.
- No redundancy across blocks — if information appears in one block, do not repeat it in another.
- Output language follows the source document's language. Do not translate unless the user explicitly requests it.

## Output routing

Save all artifacts to `~/Downloads/understand-document/<source-basename>.md`.

Create the directory if it does not exist (`mkdir -p ~/Downloads/understand-document`).

Do not save into the workspace or alongside the source document.
