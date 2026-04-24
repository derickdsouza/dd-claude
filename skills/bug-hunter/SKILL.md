---
name: bug-hunter
description: "Proactive latent defect scanning — use after merges, before releases, or in risky areas. Not for known symptoms (use debug-framework)."
---

# Bug Hunter: Proactive Multi-Level Defect Discovery

Hunt for latent defects before they are reported. Work from the cheapest, highest-signal techniques upward. Prefer precise confirmed findings over broad speculative suspicion.

## Core operating principles

- Be evidence-driven, not suspicion-driven.
- Use the cheapest technique likely to produce decisive evidence.
- Do not file speculative bugs.
- Prefer one confirmed bug over many weak leads.
- Stay within scope unless cross-module reasoning is required to confirm a defect.
- Route every confirmed finding into `bd`; do not leave actionable work in markdown files.
- Keep precision high. Low-confidence hunches stay in temporary scratch notes and are not filed.

## Use boundaries

Use this skill when:
- there is no reported symptom yet
- the task is to search, scan, audit, or hunt for defects
- the code area is unfamiliar, recently changed, risky, or historically fragile
- a recent fix suggests sibling bugs may exist
- a release or merge increased latent defect risk

Do not use this skill when:
- the user already has a concrete failure report
- the user is asking why a known behavior broke
- the code has not been written yet
- the target is a trivial script or throwaway spike

If a concrete symptom is already known, use `debug-framework` instead.

## Confirmation standard

A bug is confirmed only if **all** of the following are true:

1. **Concrete location**  
   You can identify a specific file and line, function, symbol, component boundary, or state transition.

2. **Failure statement**  
   You can clearly state:
   - what happens
   - what should happen
   - why the difference matters

3. **Reachability**  
   You can explain why the input, code path, state, caller path, or interleaving is reachable in real execution.

4. **Evidence**  
   You have at least one of:
   - minimal reproducible input or sequence
   - crash, hang, sanitizer finding, exception trace, or failing assertion
   - falsified property with a minimized counterexample
   - differential mismatch against a trusted reference
   - symbolic counterexample with feasible path conditions
   - violated invariant or demonstrated race/interleaving failure

5. **Non-duplication**  
   You checked existing related issues and found no duplicate with the same area, root cause, and symptom class.

If any of the above is missing, do not file the bug.

## Scope selection

Choose a scope explicitly before hunting:

- whole repo
- package / service / module
- recently changed files
- hotspot files
- sibling-pattern search after a recent bug fix
- blast-radius search from a known risky symbol

When the user gives no scope, prefer:
1. recently changed files
2. historically risky files
3. hotspots in risky domains such as auth, money, state, concurrency, and data integrity

## Dedup rules

Before filing, treat a finding as a duplicate if it matches:
- the same target area
- the same root cause or violated invariant
- the same symptom or failure class

Do **not** require exact file:line equality. Line numbers drift. Root cause matters more than line offsets.

## Scratch note policy

Use a single temporary `HUNT-SCRATCH.md` only for:
- ruled-out hypotheses
- low-confidence leads
- commands run
- shortlists of hotspots or suspects

Delete or discard it after triage. It is not a persistent artifact and must never become the source of truth for actionable work.

## The six levels

Hunt from cheaper to more expensive levels. Do not jump to the deepest level first unless the area strongly demands it.

```text
L1 SYNTAX       -> compiler, linter, type checker
L2 CONTRACT     -> static contract violations, required wrappers, unsafe patterns
L3 SEMANTIC     -> diff-driven behavior mismatches, caller/callee drift, blast radius
L4 RUNTIME      -> property tests, differential tests, fuzzing, assertions, stress, chaos, symbolic and concurrency checks
L5 ARCHITECTURE -> hotspots, layering, cycles, coupling, complexity, bug-prone structure
L6 HISTORICAL   -> recurrence of known bug classes, prevention-control regressions
```

## Runtime technique lanes inside L4

Within L4, choose the cheapest lane that fits the code shape.

### T1 Property-based testing
Use for:
- pure or mostly deterministic functions
- serializers and parsers with round-trip expectations
- normalization logic
- sorting, ordering, dedup, filtering
- money/math/date logic
- permission matrices

Good property templates:
- round-trip
- idempotence
- monotonicity
- no-loss / no-duplication
- bounds preservation
- equivalence under normalization
- commutativity only where it truly applies

Confirm with:
- falsified property
- minimized counterexample
- clear expected vs actual behavior

### T2 Differential testing
Use when:
- two implementations should agree
- a trusted reference exists
- there is old vs new behavior to compare
- an optimized path should match a slower reference path
- two backends, parsers, or encoders should produce equivalent results

Confirm with:
- same input
- divergent outputs or side effects
- explicit statement of which behavior is trusted and why

### T3 Fuzzing
Use when:
- the area ingests external or semi-structured input
- there is parsing, deserialization, request handling, protocol handling, or file loading
- malformed input could surface latent state or memory issues

Prioritize:
- coverage-guided fuzzing where available
- representative seed corpus
- sanitizers where supported

Confirm with:
- crash
- hang
- timeout
- sanitizer finding
- invariant violation with saved reproducer

### T4 Assertion and invariant sweep
Use when:
- contract boundaries are known
- L2 flagged suspicious areas
- hidden state corruption or boundary drift is possible

Approach:
- add assertions at boundaries or critical transitions
- run focused or full test suites
- record any invariant failure precisely

### T5 Stress / soak / race probing
Use when:
- there may be flaky behavior
- retry logic, queues, async work, parallelism, or locks are involved
- the system may leak state or fail only under repetition or concurrency

Approach:
- parallelize happy-path tests
- repeat stateful tests many times
- vary timing where feasible
- watch for flakes, races, leaks, or eventual state corruption

### T6 Chaos / failure-injection
Use when:
- external dependencies matter
- partial failure could corrupt state
- recovery semantics are safety-critical

Approach:
- kill or degrade dependencies mid-flow
- force retries, partial timeouts, or disconnects
- verify recovery and integrity, not just survival

### T7 Symbolic / solver-backed reasoning
Use when:
- the bug depends on narrow path conditions
- random exploration is unlikely to hit the issue
- branch interactions are nontrivial
- a hidden counterexample is suspected

Confirm with:
- feasible counterexample
- path-condition explanation
- violated postcondition or invariant

### T8 Concurrency / workflow invariant analysis
Use when:
- correctness depends on order, retries, interleavings, or workflow state transitions
- the module handles queues, reservations, transfers, locking, idempotency, orchestration, or async jobs

Define 2–5 invariants first, such as:
- no duplication
- no loss
- at-most-once effect
- eventual terminal state
- balance conservation
- lock exclusivity
- no illegal intermediate state

Confirm with:
- reproduced race/interleaving failure
- trace showing invariant violation
- reduced-state reasoning showing a concrete invalid transition

## Level 1 — Syntax

What it catches:
- unambiguous mechanical failures
- compile, type, lint, or static-check breakage

How:
- TypeScript/JS: `bun run typecheck`, `eslint --max-warnings 0`
- Python: `ruff check`, `mypy --strict`, `pyright`
- Rust: `cargo check`, `cargo clippy -- -D warnings`
- Go: `go vet ./...`, `staticcheck ./...`

Rules:
- If L1 is failing, stop and fix before deeper hunting.
- Exception: if `main` or trunk is broken, file a P0 `bd` bug.

Routing:
- Normal L1 failures: fix inline, no `bd`
- Broken trunk: file `bd` bug, priority P0

## Level 2 — Contract

What it catches:
- code that compiles but violates project rules or safety contracts
- forgotten `await`
- missing wrappers, decorators, transactions, guards, validators
- unhandled results
- dead code
- dangerous API usage patterns
- PII logging or unsafe direct environment access

How:
- repo lint rules and custom rules
- `mcp__jcodemunch__find_dead_code`
- `mcp__jcodemunch__get_dead_code_v2`
- `mcp__jcodemunch__search_symbols` with targeted filters such as missing decorators
- grep or structural search for known footguns

Examples:
- missing `await`
- non-atomic Redis update patterns
- interpolated SQL identifiers
- direct env access bypassing validators
- auth or transaction decorators missing on endpoints or service boundaries

Confirmation threshold:
- the pattern must be tight enough that the violation is real, not just suggestive
- if the pattern is fuzzy, gather stronger evidence before filing

Routing:
- trivial one-line fix: fix inline if obviously correct
- known bug class or historically recurring pattern: file bug and route to `debug-framework`
- uncertain pattern: keep in scratch until confirmed

## Level 3 — Semantic

What it catches:
- behavior drift after changes
- caller/callee contract mismatches
- regressions from seemingly safe changes
- API or signature evolution that existing callers still misuse
- hidden blast-radius effects

How:
- `mcp__jcodemunch__get_changed_symbols`
- `mcp__jcodemunch__get_blast_radius`
- `mcp__jcodemunch__find_references`
- `mcp__jcodemunch__get_impact_preview`
- compare changed behavior against prior assumptions and caller expectations

Key question:
“What behavior changed that existing callers or state transitions may still rely on?”

Confirmation threshold:
- identify the changed symbol or behavior
- identify the dependent caller/path
- show the mismatch between old expectation and new semantics

Routing:
- file `bd` bug
- route into `debug-framework` at Stage 0
- default complexity: simple unless runtime proof shows otherwise

## Level 4 — Runtime

What it catches:
- boundary and edge-case failures
- state leaks
- race conditions
- counterexamples hidden by broad input space
- malformed-input crashes
- recovery and resilience defects
- nondeterministic failures that static analysis cannot confirm

Execution order inside L4:
1. property-based testing if invariants are obvious
2. differential testing if a reference exists
3. fuzzing if input-driven
4. assertions/invariant sweep if boundary discipline matters
5. stress/soak for flakes or races
6. chaos for dependency/recovery correctness
7. symbolic or solver-backed reasoning when narrow path conditions block confirmation
8. concurrency/workflow invariant analysis when state ordering dominates

Stop as soon as one bug is confirmed.

Routing:
- file `bd` bug with reproducer or counterexample
- route to `debug-framework`
- complexity is usually complex unless the repro is trivial and local

## Level 5 — Architecture

What it catches:
- structurally bug-prone arrangements
- architectural drift
- fragile coupling
- hotspot concentration
- complexity cliffs
- layering violations and cycles that make future bugs likely

How:
- `mcp__jcodemunch__get_layer_violations`
- `mcp__jcodemunch__get_dependency_cycles`
- `mcp__jcodemunch__get_hotspots`
- `mcp__jcodemunch__get_coupling_metrics`
- `mcp__jcodemunch__get_symbol_complexity`
- file-size or responsibility-limit checks

Important distinction:
- L5 usually identifies **bug-prone structure**, not a confirmed concrete defect
- do not file a `bug` unless you can still meet the full confirmation standard
- otherwise file a `chore` with `architecture-review`

Examples:
- high churn + high complexity hotspot
- core module with both high afferent and efferent coupling
- cycle that hides initialization-order or state bugs
- oversized module with multiple responsibilities and known safety-sensitive logic

Routing:
- default: `chore` with `architecture-review`
- escalate to bug only if there is a concrete confirmed failure

## Level 6 — Historical

What it catches:
- recurrence of known bug classes
- regressions where earlier prevention controls eroded
- tests that still pass but no longer enforce the original invariant
- lints, types, or guards that were supposed to prevent a prior issue but are now missing or weakened

How:
1. Read `postmortems.md` for prior root causes, tokens, and prevention choices.
2. For each relevant prior incident, verify the original prevention still exists.
3. Re-run any saved or reconstructable blast-radius query for that bug class.
4. Search recent commits for recurrence tokens or code-shape drift.

Check specifically:
- lint rules still exist and are enabled
- type-level prevention is still present at the protected site
- regression tests still assert the original invariant, not a weaker proxy
- protective wrappers and guards still surround the risky path

Confirmation threshold:
- identify the historical bug class
- identify the missing or weakened prevention
- show how the risky pattern has reappeared or how the control has eroded

Routing:
- file `bd` bug with `regression` label
- route into `debug-framework` with regression flag set

## Running a hunt

Standard flow:

1. Pick scope.
2. Run L1 to completion. If L1 fails, stop and fix.
3. Run L2 to completion on the chosen scope.
4. If recent changes matter, run L3.
5. Run L6 before expensive runtime or architecture work when historical data exists.
6. Enter L4 using the cheapest fitting runtime technique lane.
7. Use L5 for structural risk after cheaper concrete checks are exhausted or when architecture is the likely root cause.
8. File each confirmed finding into `bd`.
9. Keep weak leads only in temporary scratch notes.
10. Delete or discard scratch notes after triage.

## Pre-filing evidence packet

Every filed issue must contain this evidence packet:

```text
Area: <scope or module>
Level: <L1-L6>
Technique: <syntax | contract | semantic | property | differential | fuzzing | assertions | stress | chaos | symbolic | concurrency | architecture | historical>
Confidence: <low|medium|high>
Location: <file:line | function | symbol | component>
Symptom: <what fails>
Expected: <what should happen>
Impact: <why it matters>
Why reachable: <entry path / caller / input / state / interleaving>
Pattern / trigger: <what revealed the issue>
Evidence type: <repro | crash | sanitizer | falsified property | mismatch | invariant violation | trace | static proof>
Evidence: <minimal repro, minimized input, mismatch trace, assertion failure, or reasoning chain>
Prior art: <postmortems.md#slug or none>
Duplicate check: <why this is not already covered>
Suggested route: <debug-framework or architecture-review>
Suggested complexity: <trivial | simple | complex>
Regression: <true | false>
Detected by: bug-hunter hunt <YYYY-MM-DD>
```

If any field would be vague or empty, do not file yet.

## Filing findings with `bd`

Every confirmed finding from L2+ becomes a `bd` issue. Do not track actionable findings in markdown files.

### Title format

```text
[hunt/L<N>] <file:line or component> — <one-line symptom>
```

If L4 includes a specific runtime lane and that helps clarity, you may use:

```text
[hunt/L4/<technique>] <location> — <one-line symptom>
```

### Invocation template

```bash
bd create -t <type> -p <priority>   --labels "hunt,L<N>,confidence-<low|med|high>,<cluster>,[regression],[architecture-review]"   "[hunt/L<N>] <file:line or component> — <one-line symptom>"   -d "$(cat <<'EOF'
Area: <scope or module>
Level: <L<N>>
Technique: <technique>
Confidence: <low|medium|high>
Location: <location>
Symptom: <what fails>
Expected: <what should happen>
Impact: <why it matters>
Why reachable: <entry path / caller / input / state / interleaving>
Pattern / trigger: <what revealed it>
Evidence type: <type>
Evidence: <details>
Prior art: <postmortems.md#slug or none>
Duplicate check: <why non-duplicate>
Suggested route: <debug-framework or architecture-review>
Suggested complexity: <trivial|simple|complex>
Regression: <true|false>
Detected by: bug-hunter hunt <YYYY-MM-DD>
EOF
)"
```

### Type / priority / label mapping

| Level | Type | Priority | Labels |
|---|---|---|---|
| L1 trunk broken | `bug` | P0 | `hunt,L1,trunk` |
| L1 normal | fix inline | — | — |
| L2 confirmed contract bug | `bug` | P1 or P2 | `hunt,L2,confidence-<med|high>,<cluster>` |
| L3 semantic mismatch | `bug` | P2 | `hunt,L3,confidence-med,<cluster>` |
| L4 confirmed runtime defect | `bug` | P1 or P2 | `hunt,L4,confidence-high,<cluster>` |
| L5 structural risk only | `chore` | P3 | `hunt,L5,architecture-review,<cluster>` |
| L5 concrete confirmed defect | `bug` | P1 or P2 | `hunt,L5,confidence-<med|high>,<cluster>` |
| L6 regression | `bug` | P1 | `hunt,L6,regression,confidence-high` |

Clusters should follow the same taxonomy used elsewhere, such as:
- `data`
- `logic`
- `env`
- `state`

## Confidence rubric

Use:
- **high** when there is direct runtime evidence, minimized counterexample, sanitizer/crash output, or a very strong invariant violation
- **medium** when there is strong static or semantic proof with feasible reachability but not yet direct runtime reproduction
- **low** only for scratch notes; do not file low-confidence issues unless they still satisfy the full confirmation standard

## When not to file

Do not file:
- mere code smells
- speculative race conditions without evidence
- weak test coverage by itself
- surviving mutants without a separate confirmed defect
- style issues
- vague hotspot observations without a concrete action path
- duplicate findings

## Linking to existing work

- If the finding relates to a past postmortem, include the `postmortems.md#<slug>` reference and add `regression` when appropriate.
- If the finding is related to an existing open issue, link them with `bd link`.
- If the finding belongs under an architecture-review epic, create it with `--parent <epic-id>`.

## Closing the loop

When a hunt-filed issue is resolved:
1. `debug-framework` or the owning workflow resolves the defect.
2. `debug-retrospective` writes or updates the relevant entry in `postmortems.md`.
3. Close the `bd` issue with the fix reference and postmortem slug.
4. If a prevention control was added, note that control on the issue before closing.

This keeps L6 strong over time.

## Feedback rules

Each true positive should improve future hunts:

- If L6 caught a regression, the earlier prevention was too weak; future prevention should move higher up the ladder.
- If L2 or L3 finds a recurring pattern not yet in `postmortems.md`, ensure retrospective capture after resolution.
- If L5 keeps flagging the same hotspot without concrete defects, promote it into architecture work instead of repeated hunt noise.
- If a deep runtime lane consumed significant time with no findings, record that budget in the issue or closure notes so future hunts can prioritize better.

## Anti-alarm rule

Keep signal high.

- Every filed finding must meet the confirmation standard.
- Every filed finding must have a route.
- Every filed finding must have a confidence grade.
- Findings that do not clear the threshold stay out of `bd`.
- Prefer 5 precise issues over 50 noisy ones.

Hunt cheap. Hunt often. Confirm rigorously. Route everything. Strengthen prevention after every real win.
