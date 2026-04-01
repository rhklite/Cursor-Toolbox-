---
name: design-packet-summary
description: >-
  Distills the current conversation into a structured design packet for handoff
  to another model or engineer. Use when the user says "design packet",
  "handoff", "design summary", "summary handoff", "generate a design packet",
  "documentation handoff", or "dispatch design packet".
---

# Design Packet Summary

## Instructions

When this skill is invoked, inject the following prompt into the agent and execute it against the current conversation.

---

You are generating a DESIGN PACKET from our conversation so far.

Goal:
Convert the discussion into a concise, implementation-useful technical design packet that can be handed to another model or engineer to draft final documentation.

Instructions:
- Treat this conversation as the primary source of truth.
- Distill decisions, not just summaries.
- Be concrete and specific.
- Do not invent requirements, rationale, or constraints that were not stated.
- If something is unclear or missing, add it under "Open Questions" or "Assumptions".
- Prefer crisp bullets over long prose.
- Include enough detail that another model can turn this into ADRs, specs, and implementation notes without rereading the whole chat.

Output format:

# Design Packet

## 1. Problem
- What problem are we solving?
- Why now?

## 2. Goals
- Explicit goals.

## 3. Non-goals
- What is intentionally out of scope?

## 4. Context
- Relevant background.
- Existing system constraints.
- Dependencies or surrounding architecture.

## 5. Requirements
### Functional
- Required behaviors and capabilities.

### Non-functional
- Performance, reliability, latency, cost, security, maintainability, developer experience, etc.

## 6. Proposed Design
- High-level approach.
- Key components.
- Data flow.
- Interfaces/APIs.
- Storage/state implications.
- Important implementation details.

## 7. Decision Log
For each major decision, include:
- Decision
- Why it was chosen
- Alternatives considered
- Why alternatives were rejected

## 8. Tradeoffs
- Benefits
- Costs
- Risks
- Operational complexity

## 9. Edge Cases
- Failure modes
- Corner cases
- Migration or backward-compatibility concerns

## 10. Open Questions
- Unresolved items that still need answers.

## 11. Assumptions
- Assumptions that were implied but not fully confirmed.

## 12. Recommended Next Steps
- Immediate implementation tasks.
- Validation tasks.
- Documentation tasks.

## 13. Handoff Summary
Write a short section addressed to a follow-up documentation model:
- What is already decided
- What must not be changed
- What still needs clarification
- Which sections are safe to expand into final docs

Quality bar:
- Compress aggressively, but preserve important reasoning.
- Capture actual design intent.
- Avoid vague phrases like "improve performance" unless the conversation gave specifics.
- If a claim was not stated clearly, mark it as an assumption rather than a fact.

Final instruction:
After writing the design packet, add a final section called "Missing Information I Need" with the top 5 gaps that would most improve the final technical documentation.
Write the packet so that a cheaper drafting model can produce final docs from this output alone, without rereading the entire conversation.

## Output routing

All markdown files produced by this skill — including design packets, summaries, and any other markdown output — must be saved under a `design_packet/` subfolder relative to the directory where the primary output file is written.

Rules:
- Determine the output directory from context (e.g., the project's docs output folder, the folder currently being discussed, or the workspace root if no specific folder is active).
- Append `design_packet/` to that directory and write all markdown output there.
- Create the `design_packet/` directory if it does not exist.
- Example: if the active output directory is `docs/my_project/`, write to `docs/my_project/design_packet/design_packet.md`.
- If no output directory can be determined from context, default to `design_packet/` relative to the workspace root.
