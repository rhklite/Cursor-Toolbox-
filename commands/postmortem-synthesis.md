# Postmortem Synthesis

Synthesize the Opus and Gemini postmortem reports into a unified diagnosis, then transition into the thinking partner session to plan the next iteration.

## 0. Model confirmation

Before proceeding, prompt the user: "This command runs best on **Opus Max (Ask mode)**. Are you currently on Opus Max in Ask mode? If not, please switch before we continue."

Do not proceed until the user confirms.

## 1. Locate postmortem reports

Auto-detect the most recent pair of postmortem reports in `docs/postmortem/`:
- Look for files matching `*_OP.md` and `*_GE.md` with the same timestamp prefix
- If a matching pair is found, confirm with the user: "Found reports: [OP path] and [GE path]. Synthesize these?"
- If no matching pair is found, prompt the user to provide paths to both reports

Read both reports in full.

## 2. Synthesis

Produce a unified synthesis that:
- Identifies where both analyses **agree** (these are high-confidence findings)
- Identifies where they **disagree** and explains likely reasons for the divergence
- Highlights any failure modes or insights that only one model caught
- Produces a unified **final diagnosis** combining the strongest findings from both
- Produces a unified **next experiments** list (max 3), prioritized by the strength of evidence from both analyses
- Gives a single **recommendation** sentence

Format:

```
POSTMORTEM SYNTHESIS
====================

## Agreement (high confidence)
- [Findings both models identified]

## Divergence
- [Finding]: Opus said [X], Gemini said [Y]. Likely explanation: [Z]

## Unique insights
- [Opus only]: [finding]
- [Gemini only]: [finding]

## Unified diagnosis
[Combined assessment of what happened and why]

## Next experiments (max 3)
1. [Prioritized by evidence strength from both analyses]
2. [...]
3. [...]

## Recommendation
[One sentence unified recommendation]
```

## 3. Transition to thinking partner

After presenting the synthesis, transition directly into the **rl-thinking-partner** session. Read the skill at `~/.cursor/skills/rl-thinking-partner/SKILL.md` and follow its instructions, using the synthesis findings as the starting context for the design discussion.

Skip the thinking partner's model confirmation step (the user is already on Opus Max in Ask mode, which is the correct model).

Begin the thinking partner session by reflecting back the key findings from the synthesis and asking the user which direction they want to explore for the next iteration.
