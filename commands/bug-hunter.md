---
name: bug-hunter
aliases: [bug-hunter, hunt, find-bug]
description: Proactive single-bug hunt with dedup against prior work and explicit stop conditions. Invokes the bug-hunter skill to find ONE novel confirmed bug and file it as bd.
---

# /bug-hunter — Find One Novel Bug

Invoke the `bug-hunter` skill in **single-bug mode**: hunt until you find one novel, confirmed bug, then stop and report. Dedups against prior hunts so the same finding doesn't get filed twice.

## Default Invocation (no arguments)

Use the `bug-hunter` skill. Hunt until you find **ONE novel, confirmed bug**, then stop and report.

**Dedup against prior work before scanning:**
- `bd list --label hunt --all` (both open and closed)
- `postmortems.md` entries (all of them)
- any stale `HUNT-SCRATCH.md` from prior runs

Skip any candidate finding whose **title**, **file:line**, **pattern**, or **prior-art slug** matches prior work. Track the dedup-skip count.

**Iterate freely.** Re-scanning the same file at different levels is expected and fine — L2 grep pass → L3 diff pass → L4 property test on the same module is the intended flow. Narrow scope after each empty pass. Move to a different file or package only when the current one is exhausted at all applicable levels.

**Stop on the first of:**
1. One novel, high-confidence finding filed as `bd`.
2. A novel medium-confidence finding that you can't elevate to high after 2 additional passes — file it with `confidence-med` label and stop.
3. L1–L6 exhausted across the declared scope with zero novel findings.

**Report back, in this exact shape:**

```
RESULT: <filed | exhausted>
bd ID: <pm-xxxxx> (if filed)
Title: <the bd title> (if filed)
Level: L<N>
Confidence: <low|med|high>
Scopes checked: <list of files/packages>
Dedup skips: <N candidate findings ruled out as prior work>
Passes per scope: <scope: count, ...>
```

## Arguments

```
/bug-hunter                    # default: whole-repo hunt, stop at 1 novel bug
/bug-hunter <path>             # scope-limited hunt (file or directory)
/bug-hunter --recent           # only files changed in last 7 days
/bug-hunter --level L<N>       # run only one level (e.g. --level L6 for regression check)
/bug-hunter --cluster <name>   # limit to one bug-class cluster: data|logic|env|state
/bug-hunter --no-file          # find and report, but don't create the bd issue
```

If an argument is given, apply it as scope and keep everything else from the default invocation unchanged.

## Non-Goals of This Command

- **Not a sweep.** If you want to find every bug in the repo, use the full `bug-hunter` skill directly without this command — this one stops at 1.
- **Not a debugger.** If you have a reported symptom, use `/debug` or `debug-framework` instead. This command assumes no bug has been reported yet.
- **Not a fixer.** It files the finding. Fixing goes through `debug-framework` once the `bd` issue is triaged.

## Hand-off After the Command

The filed `bd` issue carries a `suggested route` line in its body. The typical next action:

```
bd show <id>                          # read the finding
# Then either:
#   /debug <id>                       # invoke debug-framework on it
# Or manually:
#   bd update <id> --claim             # take ownership
#   Use the debug-framework skill on bd <id>
```
