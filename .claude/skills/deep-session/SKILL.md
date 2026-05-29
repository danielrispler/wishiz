---
name: deep-session
description: Full TDD development session: grills the user to understand the task and produce a plan (grill-with-docs), implements it test-first (tdd), then iterates with smart-coverage sub-agent until all Critical and High coverage gaps are closed. Use whenever the user wants to build a feature or fix a bug end-to-end, especially when they say "let's do a deep session", "full session", "build X from scratch with tests", "implement X properly", or "I want to do this right". Auto-trigger even when the user doesn't say "deep session" — if the task is non-trivial and they haven't asked for a quick fix, this is almost certainly what they want.
---

# Deep Session

A structured, three-phase workflow that takes you from fuzzy intent to working, well-tested code. Each phase has a clear exit condition and a handoff artifact. Don't rush the transitions — the value is in doing each phase fully before moving on.

---

## Phase 1: Understand (grill-with-docs)

Goal: Reach shared, precise understanding of what to build. Output: a written plan — a prioritized list of behaviors, plus the layers and technologies touched.

Invoke `Skill("grill-with-docs")` now with the user's goal as context. Let it run its full interview loop: challenge terminology against CONTEXT.md, probe edge cases, update domain docs inline.

The session ends when **both you and the user agree on**:
1. A numbered list of behaviors to implement (in implementation order)
2. Which layers and technologies are involved (e.g. "Fastify controller + Redis adapter", "React component + Zustand store")

Write this agreed plan explicitly into the conversation before moving to Phase 2. It becomes the source of truth for Phases 2 and 3.

---

## Phase 2: Implement (tdd)

Goal: Turn each agreed behavior into passing, production-quality code. One behavior at a time, never advance until GREEN.

**Skill loading:** From the Phase 1 plan, identify the layers named. Load only the skills directly relevant to those layers. Do not speculatively load skills for technologies not mentioned in the plan — that adds noise without value.

Invoke `Skill("tdd")` for each behavior in the agreed plan:
- Full red → green → refactor per behavior
- Never skip to the next behavior until the current test is passing
- Tests verify behavior through public interfaces only — no mocking internal collaborators

**Save point (hard requirement):** When all behaviors are GREEN, make a local git commit before Phase 3:

```
git commit -m "chore: complete tdd implementation phase"
```

This is mandatory. It creates a fallback in case Phase 3 coverage work breaks something.

**Context reset:** Before entering Phase 3, write a brief summary: what was built, which files changed, which behaviors now pass. Then release the red-green-refactor conversation history from active focus — Phase 3 needs only the agreed plan list and the current file state.

---

## Phase 3: Coverage Loop (smart-coverage + circuit breaker)

Goal: Close all Critical and High coverage gaps. Done means zero 🔴 Critical and zero 🟠 High gaps (or user-accepted exceptions).

Track attempts per gap so you don't spin forever:

```
gap_attempts = {}   // keyed by gap identifier (file + gap description)

LOOP:
  1. Spawn a sub-agent with Skill("smart-coverage")
     — the sub-agent runs its full 5-phase analysis and produces a gap report
  2. Read the report. If there are 🔴 Critical or 🟠 High gaps:
       For each gap:
         key = "<file>:<short-gap-name>"
         gap_attempts[key] = (gap_attempts[key] ?? 0) + 1

         If gap_attempts[key] > 3:
           PAUSE — tell the user this gap has failed 3 times; ask for manual guidance; mark as user-skipped
         Else:
           Apply Skill("tdd") to write a test that closes this specific gap
       Go to step 1
  3. If zero Critical + zero High remain (counting user-skipped as resolved):
       Exit loop — report final summary
```

**Final summary** should include:
- Which behaviors were built
- Which gaps were closed automatically
- Any gaps the user accepted after 3 attempts (with a note on why they were hard)
- The save-point commit hash from Phase 2

---

## Key principles (carry these across all three phases)

- **One thing at a time.** One question per grill turn. One test per TDD cycle. One gap per coverage attempt.
- **Public interfaces only.** Tests never reach through abstractions to assert internal state.
- **Real code paths.** No mocking internal collaborators — run the real thing.
- **Explicit handoffs.** Each phase produces a written artifact (plan list, commit, coverage report) before the next begins.
- **Circuit break, don't spin.** If something isn't working after 3 tries, surface it to the user rather than looping silently.
