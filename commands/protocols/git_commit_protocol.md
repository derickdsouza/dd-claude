# Git Commit Protocol with Verification

**Version**: 2.5.0
**Last Updated**: 2025-11-18
**Status**: MANDATORY

---

## Overview

This protocol ensures atomic commits, proper categorization, and complete verification before pushing changes. Every step is mandatory and must be completed in order.

---

## Quick Reference Checklist

**Before ANY commits:**
- [ ] Run pre-commit hooks and apply auto-fixes (Step 0)
- [ ] Run `git add -A` to stage all changes including pre-commit fixes (Step 1)
- [ ] Check for untracked files with `git ls-files --others --exclude-standard`
- [ ] Create categorization table (Step 1.5)
- [ ] Create commit plan review (Step 2.5)
- [ ] Verify all planned commits show "✅ PASS"

**Before pushing:**
- [ ] Verify `git status` shows "working tree clean"
- [ ] Verify no untracked legitimate files remain
- [ ] Run pre-push audit command (Step 5.5)
- [ ] Verify all audit results show "✅ PASS"
- [ ] Output "CATEGORIZATION AUDIT: PASSED ✅"

**Evidence to provide:**
- [ ] Pre-commit output
- [ ] Categorization table
- [ ] Commit plan review
- [ ] Pre-push audit output
- [ ] Final git status (clean)
- [ ] Untracked files verification
- [ ] List of all commits
- [ ] Push confirmation

---

## Required Protocol

When delegating to @git-operations agent to commit all changes, use this MANDATORY protocol:

```
Use @git-operations to commit all repository changes:

**STEP 0: PRE-COMMIT AUTO-FIXES (APPLY QUALITY CHECKS FIRST)**

Run pre-commit hooks to apply auto-fixes before categorization:
```bash
# Initial staging to prepare for pre-commit
git add -A

# Run pre-commit to apply auto-formatting, linting, and other fixes
pre-commit run --all-files

# Check if pre-commit made additional changes
git status
git diff --stat

# If pre-commit made changes, stage them
git add -A

# Verify all changes are now staged and formatted
git status
```

**IMPORTANT**: If pre-commit fails with errors that can't be auto-fixed:
- Fix the issues manually
- Re-stage: `git add -A`
- Re-run: `pre-commit run --all-files` 
- Repeat until pre-commit passes
- Only proceed to Step 1 after pre-commit succeeds

**STEP 1: STAGE ALL CHANGES (EXPLICIT STAGING REQUIRED)**

After pre-commit completion, ensure all changes (including auto-fixes) are staged:

```bash
git add -A
```

**STEP 1.5: MANDATORY CHANGE CATEGORIZATION (AFTER PRE-COMMIT)**

Run these commands and categorize ALL changes (including pre-commit auto-fixes):
```bash
git status
git diff --stat
git diff --name-only
git ls-files --others --exclude-standard  # CRITICAL: Check for untracked files
wc -l $(git diff --name-only) 2>/dev/null  # Check file sizes
```

**File Size Limit Check** (MANDATORY):
```bash
# Check if any files exceed 400 lines
wc -l $(git diff --name-only) 2>/dev/null | awk '$1 > 400 {print "❌ FAIL:", $2, "has", $1, "lines (exceeds 400-line limit)"}'
```

**CRITICAL**: If ANY file exceeds 400 lines, STOP and refactor before proceeding:
1. Split into logical modules
2. Extract functions to utilities
3. Move classes to separate files
4. Only proceed after all files ≤400 lines

**CRITICAL**: When counting lines, use `git diff --numstat` to get exact counts.
Only count additions (+), NOT deletions (-).

Create a categorization table:

| File | Type | Change Type | Lines Added | Commit Group |
|------|------|-------------|-------------|--------------|
| CLAUDE.md | .md | docs | +20 | Group 1: Docs |
| validation_guide.md | .md | docs | +458 | Group 1: Docs |
| validate_5_symbols.sh | .sh | feat | +81 | Group 2: Scripts |
| validate_single_symbol.py | .py | feat | +302 | Group 2: Scripts |
| comparison_engine.py | .py | refactor | +179 | Group 3: Code |

**NOTE**: Only additions (+) count toward limits. Deletions (-) are ignored.

**CATEGORIZATION RULES:**
- Different file types (.md vs .py vs .sh) = SEPARATE commits
- New files vs modified files = SEPARATE commits if >50 lines each
- Documentation vs implementation = ALWAYS separate
- MAX 5 files OR 750 lines added per commit (whichever is smaller)
- **LINE COUNTING**: Only additions (+) count toward limit; deletions (-) are ignored
- **EXCEPTION**: Documentation (.md) and JSON (.json) files have NO line limit
- Create as many commits as needed to stay within 750 lines per commit

**UNTRACKED FILES VERIFICATION** (MANDATORY):
Run `git ls-files --others --exclude-standard` to explicitly list all untracked files and categorize each as either:
- ✅ **COMMIT**: Legitimate new files that should be included
- ✅ **IGNORE**: Temporary files (backups, logs, etc.) that should remain untracked

**VALIDATION:**
If ANY group exceeds limits, split further.
Agent MUST output categorization table before creating ANY commits.

**COMMIT SIZE LIMITS (MANDATORY):**
- ❌ >5 files in one commit = VIOLATION (split required)
- ❌ >750 total lines added (+) = VIOLATION (split required)
- ❌ **LINE COUNTING**: Only count additions (+), ignore deletions (-)
- ❌ **EXCEPTION**: .md and .json files have NO line limit
- ❌ Mix of .md + .py/.sh = VIOLATION (separate required)
- ❌ "New files" + "Modified files" >750 lines added = VIOLATION (separate required)
- ✅ Create as many commits as needed to stay within limits

**RED FLAGS - If detected, STOP and re-categorize:**
- Commit message says "docs" but contains .py/.sh files
- Commit has 10+ files
- Commit has 1000+ lines added (except .md/.json files)
- Multiple unrelated directories touched
- Untracked files not categorized

**STEP 2: ANALYZE AND GROUP CHANGES**

Using categorization table from Step 1.5:
- Identify smallest possible set of related changes
- Group by functionality and create atomic commits
- Order by dependencies: most independent changes first → most dependent last

**CHANGE CATEGORIZATION MATRIX:**

| Files Changed | Commit Type | Examples |
|---------------|-------------|----------|
| Only .md files | `docs:` | README, specs, plans |
| Only .py files (new) | `feat:` | New scripts/modules |
| Only .py files (modified) | `refactor:` or `fix:` | Code changes |
| .sh + .py (new tools) | `feat:` | Validation tooling |
| Mix of .md + code | SPLIT INTO SEPARATE COMMITS | Never combine |
| >5 files OR >750 lines | SPLIT INTO MULTIPLE COMMITS | Regardless of type (except .md/.json) |

**STEP 2.5: COMMIT PLAN REVIEW (BEFORE EXECUTION)**

Before creating commits, output this plan:

```
COMMIT PLAN REVIEW:
==================
Commit 1: feat: implement new trading algorithm
  Files: src/algo.py, src/strategy.py, src/executor.py, src/utils.py, src/config.py, src/metrics.py
  Lines: +1234 -156
  Validation: ❌ FAIL - Exceeds 5 file limit, must split

Commit 1A: feat: implement core trading algorithm
  Files: src/algo.py, src/strategy.py, src/executor.py
  Lines: +245 -89 (only +245 counts toward limit)
  Validation: ✅ PASS (3 files, 245 lines added - within 750 limit)

Commit 1B: feat: add algorithm utilities and configuration
  Files: src/utils.py, src/config.py, src/metrics.py
  Lines: +289 -67 (only +289 counts toward limit)
  Validation: ✅ PASS (3 files, 289 lines added - within 750 limit)

Commit 2: docs: add comprehensive API documentation
  Files: docs/api_reference.md, docs/trading_guide.md
  Lines: +2458 -0
  Validation: ✅ PASS (.md files exempt from line limit)

Commit 3: chore: update configuration files
  Files: config/settings.json, config/defaults.json
  Lines: +1567 -234
  Validation: ✅ PASS (.json files exempt from line limit)

PLAN APPROVED: YES
```

Only proceed if ALL commits show "Validation: ✅ PASS"

Agent MUST output commit plan before executing any commits.

**STEP 3: CREATE COMMITS**

Use conventional commit format (feat:, fix:, docs:, refactor:, chore:, etc.)
Each commit should be atomic and logically grouped

**CRITICAL**: Use `--no-verify` flag to skip pre-commit hooks (already ran in Step 0)

Example:
```bash
git add CLAUDE.md .claude/CLAUDE.md
git commit --no-verify -m "docs: update project configuration

- Update global CLAUDE.md configuration
- Remove .claude/CLAUDE.md (moved to project root)

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

**STEP 4: MANDATORY VERIFICATION LOOP**

After all commits, run: git status
Verify output shows: "nothing to commit, working tree clean"

**CRITICAL - Untracked Files Check**:
```bash
git status --short
git ls-files --others --exclude-standard
```

Categorize any untracked files found:
- ✅ **COMMIT**: Legitimate new files → stage and commit them
- ✅ **IGNORE**: Temporary files (backups, logs, etc.) → leave untracked

If NOT clean: identify remaining changes, stage them, commit them
Repeat until working tree is CLEAN and no legitimate untracked files remain

**STEP 5: ENFORCEMENT CHECKPOINT (MANDATORY BEFORE PUSH)**

Run: `git log --oneline -N` (where N = number of commits created)

For EACH commit, verify:
- ✅ Commit message type matches file types
- ✅ File count ≤ 5
- ✅ Total lines added (+) ≤ 750 (except .md/.json files; deletions don't count)
- ✅ No mixing of docs + code
- ✅ Logical grouping makes sense

If ANY check fails: `git reset --soft HEAD~N` and re-do from Step 1.5

**STEP 5.5: MANDATORY PRE-PUSH CATEGORIZATION AUDIT**

Before pushing, run this verification command:

```bash
# Quick Audit Command
git log -3 --format="Commit: %h - %s" --numstat | \
awk '/^Commit:/ {if (NR>1) print files" files, "total" lines - "verdict; commit=$0; files=0; total=0; next}
     /^[0-9]/ {files++; total+=$1+$2}
     END {print files" files, "total" lines - "(files>5||total>750?"❌ FAIL":"✅ PASS")}' && \
echo "" && \
echo "File type mix check:" && \
for i in 1 2 3; do
  echo "Commit -$i:"
  git log -$i --format="" --name-only | head -20 | grep -E "\.(md|py|sh)$" | sed 's/.*\./  ./' | sort | uniq -c
done
```

Expected output format:
```
4 files, 245 lines - ✅ PASS
3 files, 189 lines - ✅ PASS
2 files, 87 lines - ✅ PASS

File type mix check:
Commit -1:
   4 .md
Commit -2:
   2 .py
   1 .sh
Commit -3:
   2 .py
```

**RED FLAGS IN AUDIT:**
- Same commit shows both .md AND .py files = ❌ FAIL
- Any commit shows >5 files or >750 lines added (except .md/.json) = ❌ FAIL
- Mix of new + modified files >750 lines added total (except .md/.json) = ❌ FAIL
- **REMINDER**: Only additions (+) count; deletions (-) are ignored

**MANDATORY AUDIT CHECKLIST:**
```
[ ] Pre-commit hooks executed successfully (Step 0)
[ ] Categorization table was created in Step 1.5
[ ] File size limit check passed (all files ≤400 lines)
[ ] Each commit matches planned category from table
[ ] No commit exceeds 5 files
[ ] No commit exceeds 750 lines added (except .md/.json files)
[ ] Line counting verified: only additions (+) counted, deletions (-) ignored
[ ] No mixing of .md + .py/.sh files
[ ] All commits validated with "✅ PASS"
[ ] All commits created with --no-verify flag
[ ] Audit output shows no RED FLAGS
[ ] UNTRACKED FILES AUDIT: `git ls-files --others --exclude-standard | wc -l` shows 0 (only expected temporary files should remain)
```

**ENFORCEMENT:**
- If ANY checkbox is unchecked: STOP, do NOT push
- If ANY commit shows "❌ FAIL": Run `git reset --soft HEAD~N` and restart from Step 1.5
- Agent MUST output: "CATEGORIZATION AUDIT: PASSED ✅" before pushing

**STEP 6: PUSH CHANGES**

Only push after verification confirms clean working tree AND audit passes

```bash
# Only after audit passes
echo "CATEGORIZATION AUDIT: PASSED ✅ - Proceeding with push"
git push --no-verify
```

**CRITICAL**:
- Use `--force-with-lease` only when rebasing/amending pushed commits
- Default push command: `git push --no-verify` (since hooks already ran)
- If audit output is NOT present in agent response = CRITICAL FAILURE

**STEP 7: REPORT EVIDENCE (REQUIRED)**

Provide:
- Pre-commit output from Step 0
- Categorization table from Step 1.5
- File size check results
- Untracked files verification
- Commit plan review from Step 2.5
- Final `git status` output showing "working tree clean"
- Pre-push audit output showing all "✅ PASS"
- List of ALL commits created with their commit messages
- Confirmation that push completed successfully

**SUCCESS CRITERIA:**
- ✅ Pre-commit hooks executed successfully and auto-fixes applied
- ✅ All files ≤400 lines (refactored if needed)
- ✅ Categorization table created and validated (after pre-commit)
- ✅ Untracked files verification completed - all legitimate files committed
- ✅ Commit plan reviewed and approved
- ✅ All commits ≤5 files AND ≤750 lines added (except .md/.json exempt from line limit)
- ✅ Line counting correct: only additions (+) counted, deletions (-) ignored
- ✅ No mixing of file types (.md separate from .py/.sh)
- ✅ All commits created with `--no-verify` flag
- ✅ Pre-push audit shows all "✅ PASS"
- ✅ `git status` shows "nothing to commit, working tree clean"
- ✅ All commits pushed to remote with `--no-verify`
- ✅ Evidence (pre-commit output, categorization, plan, audit, git status) provided in response

**FAILURE = CRITICAL ERROR:**
- Pre-commit hooks not executed or failed
- Any file exceeding 400-line limit not refactored
- Missing categorization table
- Missing commit plan review
- Missing pre-push audit output
- Any commit violating size/type limits
- Commits created without `--no-verify` flag
- Working tree not clean after commits
- Untracked legitimate files not committed
- Agent proceeding without "CATEGORIZATION AUDIT: PASSED ✅" message
```

---

## Why This Protocol Matters

**Problem**: Git agents often fail by:
- Not running pre-commit hooks before categorization
- Only staging modified tracked files, missing deletions and new files
- Missing untracked files that should be committed
- Grouping unrelated changes into single commits (docs + code)
- Exceeding reasonable commit sizes (1000+ lines added in one commit)
- Not verifying completion, leaving uncommitted changes behind
- Not validating commits before pushing

**Solution**: Explicit pre-commit + staging + categorization + untracked files check + size limits (counting only additions, not deletions) + audit ensures 100% of changes are properly committed in atomic, reviewable units.

**Line Counting Policy**: Only additions (+) count toward the 750-line limit. Deletions (-) are ignored to encourage cleanup and refactoring without penalty.

---

## Examples

### Example 1: Simple Documentation Update

**Categorization Table:**
```
| File       | Type | Change Type | Lines Added | Commit Group  |
|------------|------|-------------|-------------|---------------|
| README.md  | .md  | docs        | +45         | Group 1: Docs |
```

**Note**: Deletions (-12) not shown as they don't count toward limit

**Commit Plan:**
```
COMMIT PLAN REVIEW:
==================
Commit 1: docs: update README with new setup instructions
  Files: README.md
  Lines: +45 -12 (only +45 counts toward limit)
  Validation: ✅ PASS (.md files exempt from line limit anyway)

PLAN APPROVED: YES
```

**Commit:**
```bash
git commit --no-verify -m "docs: update README with new setup instructions

- Add Docker setup section
- Update installation steps
- Fix broken links

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

### Example 2: Mixed Changes Requiring Split

**Categorization Table:**
```
| File                  | Type | Change Type | Lines Added | Commit Group      |
|-----------------------|------|-------------|-------------|-------------------|
| README.md             | .md  | docs        | +23         | Group 1: Docs     |
| specs/api_spec.md     | .md  | docs        | +156        | Group 1: Docs     |
| src/api.py            | .py  | feat        | +234        | Group 2: Features |
| tests/test_api.py     | .py  | test        | +189        | Group 3: Tests    |
```

**Note**: Deletions not shown as they don't count toward limit

**Commit Plan:**
```
COMMIT PLAN REVIEW:
==================
Commit 1: docs: update README and add API specification
  Files: README.md, specs/api_spec.md
  Lines: +179 -5 (only +179 counts toward limit)
  Validation: ✅ PASS (2 files, 179 lines added - both .md files exempt anyway)

Commit 2: feat: add new API endpoint
  Files: src/api.py
  Lines: +234 -0 (only +234 counts toward limit)
  Validation: ✅ PASS (1 file, 234 lines added - within 750 limit)

Commit 3: test: add API endpoint tests
  Files: tests/test_api.py
  Lines: +189 -0 (only +189 counts toward limit)
  Validation: ✅ PASS (1 file, 189 lines added - within 750 limit)

PLAN APPROVED: YES
```

---

## Troubleshooting

### Problem: Categorization table shows commit >750 lines added (non-.md/.json files)

**Solution:** Split the commit further by:
1. Separating new files from modified files
2. Grouping by subdirectory/module
3. Creating incremental commits for large new files
4. Note: .md and .json files are exempt from line limits
5. Remember: Only additions (+) count; deletions (-) are ignored

### Problem: Pre-push audit shows "❌ FAIL"

**Solution:**
```bash
# Reset commits
git reset --soft HEAD~N  # N = number of commits to undo

# Return to Step 1.5
# Re-categorize with smaller groups
# Create new commits following the limits
```

### Problem: Mix of .md and .py files in same logical change

**Solution:** Create separate commits:
```bash
# Commit 1: Documentation
git add *.md
git commit --no-verify -m "docs: add feature documentation"

# Commit 2: Implementation
git add src/*.py
git commit --no-verify -m "feat: implement new feature"

# Commit 3: Tests
git add tests/*.py
git commit --no-verify -m "test: add feature tests"
```

### Problem: Pre-commit hooks fail and can't auto-fix

**Solution:** Manual intervention required:
```bash
# If pre-commit fails, fix the reported issues manually
# Example: Fix linting errors, add missing docstrings, etc.

# After manual fixes, re-stage and re-run
git add -A
pre-commit run --all-files

# Repeat until pre-commit passes, then proceed to Step 1
```

### Problem: File exceeds 400 line limit during categorization

**Solution:** Refactor before committing (MANDATORY from CLAUDE.md):
```bash
# Check line counts during categorization
wc -l src/*.py

# If ANY file >400 lines: STOP and refactor
# 1. Split into logical modules
# 2. Extract functions to utilities
# 3. Move classes to separate files
# 4. Only proceed after all files ≤400 lines
```

### Problem: Untracked files discovered after commits

**Solution:** Categorize and handle appropriately:
```bash
# List untracked files
git ls-files --others --exclude-standard

# For each file, determine:
# - COMMIT: Legitimate file → git add <file> && git commit --no-verify
# - IGNORE: Temporary file → add to .gitignore or leave untracked
```

---

## Version History

| Version | Date       | Changes                                                    |
|---------|------------|------------------------------------------------------------|
| 2.5.0   | 2025-11-18 | Updated limits: FILE 400 lines (was 275), COMMIT 750 lines (was 300) |
| 2.4.0   | 2025-10-06 | Added untracked files verification, synchronized with docs/commit_workflow.md |
| 2.3.0   | 2025-01-06 | Cleaned up: removed AI-specific content, pure git protocol |
| 2.2.0   | 2025-01-06 | Multi-AI compatibility, CLAUDE.md integration, universal triggers |
| 2.1.0   | 2025-01-06 | Added Step 0 for pre-commit hooks, --no-verify for commits|
| 2.0.0   | 2025-01-03 | Enhanced with examples, troubleshooting, quick reference  |
| 1.0.0   | 2025-01-03 | Initial protocol with categorization, size limits, audit  |

---

**Maintained by**: Developer Experience Team
