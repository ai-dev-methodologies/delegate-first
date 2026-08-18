---
name: delegate-first
description: Enforces that the main session acts only as planner, delegator, reviewer, and judge — routing all execution work (edits, writes, execution-style commands) to subagents with a task-appropriate model and reasoning effort. Use ONLY when the user explicitly invokes this skill by name (/delegate-first) or explicitly asks for the delegation discipline. Do not activate proactively.
---

# Delegate First

> Explicit-invocation only — do not self-trigger on task shape. Apply this discipline only when the user names this skill or explicitly asks for it.

## Principle

The main session runs a high-cost frontier model. Its job is planning, delegating, reviewing, and judging — not execution.

Before any Edit, Write, or execution-style Bash call, ask: **"Can this be delegated?"**
The only exceptions are a one-off read for context and a single verification command run to confirm a subagent's claim.

## Main-session reasoning-effort policy

The main session's model and reasoning-effort *setting* are the user's call (session config) — this skill does not set them. What this skill governs is **reasoning discipline within a turn**: how hard the main session should think before acting, per turn type.

| Turn type | Reasoning depth |
|---|---|
| Mechanical relay, status check, or idle-notification response | Minimal — answer immediately |
| Review of a subagent's output | Medium |
| Judgment, design, or escalation diagnosis | Deep |

Delegated effort is a separate matter, decided by [references/routing-matrix.md](references/routing-matrix.md) — not by this section. The execution path determines whether effort can even be specified: Workflow `agent()`'s `effort` param, `codex exec`'s `model_reasoning_effort`, or (for ad-hoc Agent calls) not at all — tier agents get effort from their frontmatter instead — see routing-matrix.md for details.

## Flow checklist

Copy this into your response and check off as you go:

```
Delegation Progress:
- [ ] 1. Decompose the task and classify its type
- [ ] 2. Pick model + effort + execution path (routing-matrix.md) — if effort matters, prefer a tier agent or Workflow/codex path
- [ ] 3. Delegate with a scoped prompt (prompt-templates.md) — and log it: agent/role/model/effort/path appended to the project delegation log (path is a per-project parameter — default docs/handoff/delegation-log.md, see the installing project's README); effort not specifiable on ad-hoc Agent calls → record "(default)"
- [ ] 4. Review: don't trust self-report — reproduce key claims (grep/run)
- [ ] 5. Judge: pass / re-delegate (strengthen prompt) / escalate
```

**Step 1 — Decompose & classify.** Split the task into units of one type each: exploration/extraction, doc editing/structuring, general implementation, first-pass review, adversarial verification/judgment, or architecture/legal/money/authorization.

**Step 2 — Route.** See [references/routing-matrix.md](references/routing-matrix.md) for model, effort, and execution path per task type. If effort matters for the outcome, pick a tier agent (`subagent_type`) or the Workflow `agent()` / `codex exec` path at this step — ad-hoc Agent calls can't set effort, so decide before delegating, not at logging time. When calling a tier agent, prefer omitting `model` (passing it overrides the definition's `model`, though `effort`/`tools` survive) — this preference only holds when every registered hook's pinned list includes that tier, and a named spawn (passing `name`) does not preserve `effort` even so; see routing-matrix.md.

**Step 3 — Delegate.** See [references/prompt-templates.md](references/prompt-templates.md) for the two standard templates (read-only investigation, implementation/edit). Every delegation prompt must state: role in one line, working directory + boundaries (what must not be touched), forbidden system-level commands, required evidence (an "it doesn't exist" claim must state the search scope), a completion checklist, the expected output format, and — for verdict/review delegations — a timebox.

**Step 4 — Review.** A subagent's self-report is not evidence on its own. Reproduce its central claim yourself — grep the file it says it edited, run the test it says passes, read the diff it says exists.

**Step 5 — Judge.** Pass and move on, re-delegate with a strengthened prompt, or escalate per the ladder below.

## Escalation ladder

When a subagent's output fails review, diagnose the cause before retrying:

| Cause | Fix |
|---|---|
| Instructions unclear | Same model, strengthen the prompt |
| Insufficient capability | Raise model and/or effort |
| Scope too large | Split into smaller units |

Always strengthen the prompt alongside any model upgrade — raising the model without fixing the prompt just repeats the same failure at higher cost.

- Same root cause fails twice → escalate model/effort unconditionally on the retry.
- Fails a 3rd time → stop delegating, report the blocker to the user.

## Idle recovery

Delegating a judgment call means setting a timebox — "act if nothing arrives by then," not "wait for notification." Pick the box at delegation time; long-running judgments deserve a longer box than a quick lookup, but the box must exist.

- Detect the expiry by polling — `ListAgents`/`Monitor` when the harness provides them — not by waiting for a notification that may not arrive.
- No response by the timebox → `SendMessage` (when the harness provides it) the same agent to re-demand the verdict (context preserved).
- No response to the re-demand → re-delegate to a fresh agent with a strengthened prompt.
- If the original agent's verdict arrives late, after re-delegation, it is still valid — review both reports, and let the more adverse verdict govern until it is rebutted. Recovery replaces silence, not the verdict.
- If the re-delegated agent is also unresponsive → stop and report the blocker to the user. For a verdict under the fable-forced triggers, recovery's endpoint is the user, not self-approval.
- Never block on a notification that may not arrive — waiting is not progress. This does not mean skipping the verification gate, only using recovery to reach it.

## Mandatory top-tier-model (fable) triggers

The main session's own model is a user setting (session config) — it may be `fable`, `opus`, or anything else. This skill does not assume which. Regardless of the main session's model, these 5 judgment types must go through the top-tier model (`fable`): if the main session already is `fable`, it performs them directly; otherwise, it delegates to a `fable` subagent.

1. ADR-level decisions
2. Shipping/release gates
3. Adversarial verification
4. Final-instance escalation review
5. Legal, financial, permission/authorization, or security judgment calls

## Prohibited

Do not auto-recalibrate the routing matrix from delegation logs. Routing stays principle-based — update [references/routing-matrix.md](references/routing-matrix.md) by hand, immediately, when a routing choice turns out wrong. For feedback-loop design beyond what's in this skill, see the Anthropic Agent Skills best-practices guide: https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices
