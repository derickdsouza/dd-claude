---
name: scientific-debugging
description: "Scientific method bug investigation — hypothesis testing, evidence gathering, bias avoidance."
---

# Scientific Debugging

## Philosophy

### User = Reporter, You = Investigator

The user knows what they expected, what actually happened, error messages, and when it started. The user does NOT know the cause, which file has the problem, or what the fix should be. Ask about experience. Investigate the cause yourself.

### Foundation Principles

- **What do you know for certain?** Observable facts, not assumptions.
- **What are you assuming?** "This library should work this way" — have you verified?
- **Strip away everything you think you know.** Build understanding from observable facts.

### Cognitive Biases to Avoid

| Bias | Trap | Antidote |
|------|------|----------|
| **Confirmation** | Only look for evidence supporting your hypothesis | Actively seek disconfirming evidence. "What would prove me wrong?" |
| **Anchoring** | First explanation becomes your anchor | Generate 3+ independent hypotheses before investigating any |
| **Availability** | Recent bugs lead you to assume similar cause | Treat each bug as novel until evidence suggests otherwise |
| **Sunk Cost** | Spent 2 hours on one path, keep going despite evidence | Every 30 min: "If I started fresh, is this still the path I'd take?" |

### Systematic Investigation Disciplines

**Change one variable:** Make one change, test, observe, document, repeat. Multiple changes = no idea what mattered.

**Complete reading:** Read entire functions, not just "relevant" lines. Read imports, config, tests. Skimming misses crucial details.

**Embrace not knowing:** "I don't know why this fails" = good (now you can investigate). "It must be X" = dangerous (you've stopped thinking).

### Meta-Debugging: Your Own Code

When debugging code you wrote, you fight your own mental model.

- **Treat your code as foreign** — read it as if someone else wrote it
- **Question your design decisions** — they are hypotheses, not facts
- **Admit your mental model might be wrong** — the code's behavior is truth; your model is a guess
- **Prioritize code you touched** — if you modified 100 lines and something breaks, those are prime suspects
- **The hardest admission:** "I implemented this wrong." Not "requirements were unclear."

### When to Restart

Consider starting over when:
1. 2+ hours with no progress — you're likely tunnel-visioned
2. 3+ "fixes" that didn't work — your mental model is wrong
3. You can't explain the current behavior — don't add changes on top of confusion
4. You're debugging the debugger — something fundamental is wrong
5. The fix works but you don't know why — this isn't fixed, this is luck

**Restart protocol:** Write down what you know for certain, what you've ruled out, then list new hypotheses (different from before) and begin again from evidence gathering.

---

## Hypothesis Testing

### Falsifiability Requirement

A good hypothesis can be proven wrong. If you can't design an experiment to disprove it, it's not useful.

**Bad (unfalsifiable):** "Something is wrong with the state" / "The timing is off" / "There's a race condition somewhere"

**Good (falsifiable):** "User state is reset because component remounts when route changes" / "API call completes after unmount, causing state update on unmounted component"

The difference is specificity. Good hypotheses make specific, testable claims.

### Forming Hypotheses

1. **Observe precisely:** Not "it's broken" but "counter shows 3 when clicking once, should show 1"
2. **Ask "What could cause this?"** — list every possible cause (don't judge yet)
3. **Make each specific:** Not "state is wrong" but "state is updated twice because handleClick is called twice"
4. **Identify evidence:** What would support/refute each hypothesis?

### Experimental Design Framework

For each hypothesis:
1. **Prediction:** If H is true, I will observe X
2. **Test setup:** What do I need to do?
3. **Measurement:** What exactly am I measuring?
4. **Success criteria:** What confirms H? What refutes H?
5. **Run:** Execute the test
6. **Observe:** Record what actually happened
7. **Conclude:** Does this support or refute H?

**One hypothesis at a time.** If you change three things and it works, you don't know which one fixed it.

### Evidence Quality

**Strong evidence:** Directly observable, repeatable, unambiguous, independent (e.g., "happens even in fresh environment with no cache").

**Weak evidence:** Hearsay, non-repeatable, ambiguous, confounded (e.g., "works after restart AND cache clear AND package update").

### When to Act

Act when you can answer YES to all:
1. Understand the mechanism? Not just "what fails" but "why it fails"
2. Reproduce reliably? Either always reproduces, or you understand trigger conditions
3. Have evidence, not just theory? You've observed directly, not guessing
4. Ruled out alternatives? Evidence contradicts other hypotheses

### Recovery from Wrong Hypotheses

1. **Acknowledge explicitly** — "This hypothesis was wrong because [evidence]"
2. **Extract the learning** — What did this rule out? What new information?
3. **Revise understanding** — Update mental model
4. **Form new hypotheses** — Based on what you now know
5. **Don't get attached** — Being wrong quickly is better than being wrong slowly

### Multiple Hypotheses Strategy

Don't fall in love with your first hypothesis. Design experiments that differentiate between competing hypotheses. One well-designed experiment can rule out multiple hypotheses simultaneously.

---

## Investigation Techniques

### Binary Search / Divide and Conquer

**When:** Large codebase, long execution path, many possible failure points.

Cut problem space in half repeatedly. Identify boundaries (where works, where fails), add logging/testing at midpoint, determine which half contains the bug, repeat until exact line.

### Rubber Duck Debugging

**When:** Stuck, confused, mental model doesn't match reality.

Explain the problem in complete detail: what the system should do, what it actually does, what you think the cause is, the code path, what you've verified, and what you're assuming. Often you'll spot the bug mid-explanation.

### Minimal Reproduction

**When:** Complex system, many moving parts, unclear which part fails.

Copy failing code to new file. Remove one piece at a time. Test after each removal. If it still reproduces, keep the removal. Repeat until bare minimum. Bug is now obvious in stripped-down code.

### Working Backwards

**When:** You know correct output, don't know why you're not getting it.

Start from desired end state, trace backwards through the call stack. At each step, test with expected input — if output is correct, the bug is earlier; if not, the bug is here. Find the divergence point.

### Differential Debugging

**When:** Something used to work and now doesn't, or works in one environment but not another.

**Time-based:** What changed in code, environment, data, configuration?
**Environment-based:** Configuration values, env vars, network conditions, data volume, third-party service behavior.

List differences, test each in isolation, find the difference that causes failure.

### Observability First

**When:** Always. Before making any fix.

Add visibility before changing behavior: strategic logging at key points, assertion checks, timing measurements, stack traces. Workflow: add logging, run code, observe output, form hypothesis, then make changes.

### Comment Out Everything

**When:** Many possible interactions, unclear which code causes issue.

Comment out everything in function/file. Verify bug is gone. Uncomment one piece at a time. After each uncomment, test. When bug returns, you found the culprit.

### Git Bisect

**When:** Feature worked in past, broke at unknown commit.

Binary search through git history. Mark current as bad, a known-good commit as good. Git checks out the middle. Test and mark. Repeat. 100 commits = ~7 tests to find the breaking commit.

### Technique Selection

| Situation | Technique |
|-----------|-----------|
| Large codebase, many files | Binary search |
| Confused about what's happening | Rubber duck, Observability first |
| Complex system, many interactions | Minimal reproduction |
| Know the desired output | Working backwards |
| Used to work, now doesn't | Differential debugging, Git bisect |
| Many possible causes | Comment out everything, Binary search |
| Always | Observability first (before making changes) |

Techniques compose. A typical flow: differential debugging to identify what changed, binary search to narrow where in code, observability to add logging at that point, rubber duck to articulate what you're seeing, minimal reproduction to isolate just that behavior, working backwards to find root cause.

---

## Verification Patterns

### What "Verified" Means

A fix is verified when ALL are true:
1. Original issue no longer occurs (exact reproduction steps now produce correct behavior)
2. You understand why the fix works (can explain the mechanism)
3. Related functionality still works (regression testing passes)
4. Fix is stable (works consistently, not "worked once")

### Test-First Debugging

Write a failing test that reproduces the bug, then fix until the test passes. This proves you can reproduce the bug, provides automatic verification, prevents future regression, and forces precise understanding.

### Stability Testing

For intermittent bugs, run the test many times. If it fails even once, it's not fixed. Use parallel execution and random delays to expose timing bugs.

### Verification Mindset

**Assume your fix is wrong until proven otherwise.** Ask: "How could this fix fail?", "What haven't I tested?", "What am I assuming?", "Would this survive production?"

**Red flag phrases:** "It seems to work", "I think it's fixed", "Looks good to me"

**Trust-building phrases:** "Verified N times — zero failures", "All tests pass including new regression test", "Root cause was X, fix addresses X directly"

---

## Research vs Reasoning Decision Tree

```
Is this an error message I don't recognize?
  YES -> Search the error message
  NO  ->
Is this library/framework behavior I don't understand?
  YES -> Check official docs, upstream issues
  NO  ->
Is this code I/my team wrote?
  YES -> Reason through it (logging, tracing, hypothesis testing)
  NO  ->
Is this a platform/environment difference?
  YES -> Research platform-specific behavior
  NO  ->
Can I observe the behavior directly?
  YES -> Add observability and reason through it
  NO  -> Research the domain/concept first, then reason
```

**Balance:** Start with quick research (5-10 min). If no answers, switch to reasoning. If reasoning reveals gaps, research those specific gaps. Alternate as needed.

**Research trap:** Hours reading docs tangential to your bug.
**Reasoning trap:** Hours reading code when the answer is well-documented.
