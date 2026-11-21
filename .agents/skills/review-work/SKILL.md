---
name: review-work
description: Review a completed or interrupted PassArc task from the original prompt to the delivered result. Use for a work retrospective, including 振り返り or 作業レビュー, when the user wants to identify stale guidance, missing context, avoidable investigation, or handoff gaps and propose improvements for future Codex sessions.
---

# Review work

Identify the smallest durable changes that would help the next Codex session reach the intended result with less investigation or rework. Use the user's language for the review.

## Reconstruct the task

- Read the original request and later corrections in order. Record the requested outcome, relevant constraints, and what was actually delivered or left pending. Use the available conversation, tool results, and scoped artifacts such as Git status, commits, diffs, or PR metadata. Mark gaps in the record when earlier inputs or actions are unavailable.
- For each material detour, identify the decision that stalled or went wrong, the information available at that point, and where the resolving evidence eventually came from. Describe observable costs such as repeated commands, extra questions, or rework. Quantify them only when the record supports it.
- Check whether guidance was stale, absent, hard to find, ambiguous, or already available but skipped. Verify current guidance against the relevant script, configuration, or other authoritative source. Distinguish repository guidance gaps from one-off workstation failures, tool restrictions, and changes in the user's request. Treat causes as hypotheses when the evidence is incomplete.
- Compare the delivered result with the intended outcome. Where relevant, reconcile local tracked and untracked files, committed content, and published PR content using the checks in the repository's `AGENTS.md`. Record which checks actually ran.

## Propose reusable improvements

For each finding, give the observed event and its evidence, its effect on the task, and a concrete change that would have helped at the decision point. Name an existing file or workflow step to update and suggest wording or a verification command when useful. Prefer `AGENTS.md` for repository-wide working rules, the existing development notes for reproducible technical details, and the relevant skill for specialized workflows. Where the source of truth already exists, prefer a short pointer or a correction at that source.

End the review with a short, prioritized list of proposals the user can act on. For each proposal, name the exact file or workflow step, show a suggested edit or command when the evidence supports one, and state how to verify that it helps. Identify which proposals are ready to apply and which need more evidence. Mention existing fixes with their delivery status so the user can see what is still pending.

Prioritize impact on delivery and likelihood of recurrence. Merge findings with the same cause. If there is no supported reusable improvement, say so. Apply proposals when the user requests implementation.
