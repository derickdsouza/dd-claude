# Create-PR Prompt (drop into `.beads/prompts/create-pr.md`)

You are creating a GitHub pull request for a shipped beads issue. Be terse,
factual, and deterministic.

## Inputs (from environment)

- `$BEAD_ID` — the beads issue ID (e.g. `myproject-xxxxx`)
- `$BRANCH` — the branch name to PR
- `$FORCE_HOLD` — if `"true"`, you MUST set `HOLD=true` regardless of heuristics

## Steps

1. **Idempotency check.** Run `gh pr list --head "$BRANCH" --state open --json number`. If a PR already exists, print `PR_NUMBER=<n>` and `HOLD=false` and stop.

2. **Refresh the merge base.**
   - `git fetch origin main --prune`
   - If fetch fails, continue only if `origin/main` already exists locally.

3. **Gather context.**
   - `bd show "$BEAD_ID"` — bead title, description, type, priority
   - `git log origin/main..origin/"$BRANCH" --oneline` — commit messages on the branch
   - `git diff --stat origin/main...origin/"$BRANCH"` — files + lines changed
   - `git diff --name-only origin/main...origin/"$BRANCH"` — file list for risk check

   Never compare against local `main`; it may be stale in long-lived worktrees.
   Use `origin/main` for every diff/log/base check in this prompt.

4. **Risk classification (HOLD)** — does this PR need human review before merging?
   Set `HOLD=true` if ANY of these match (first match wins):

   Tune the globs for your repo:

   - `$FORCE_HOLD == "true"`
   - **Schema/DB**: any file matches `packages/backend/src/db/schema/**` or `**/migrations/**`
   - **Deploy scripts**: any file matches `scripts/deploy*.sh`, `scripts/rollback.sh`, or your CI config paths
   - **Size**: `git diff --shortstat` reports >300 insertions+deletions
   - **Breadth**: `git diff --name-only` reports >5 files
   - **Explicit keywords**: bead description contains "requires human review" or "breaking change"

   Else `HOLD=false`.

5. **Compose PR title.** Use the bead title directly, suffixed with the bead ID
   in parentheses. Under 70 characters if possible. Example:
   `fix(orms): freeze-gate blocks handoff (myproject-9t2ig)`

8. **Compose PR body** using this template:

   ```markdown
   ## Summary
   <one-sentence description from bead>

   ## Bead
   - **ID:** $BEAD_ID
   - **Type / Priority:** <type> / <priority>
   - **Closed by:** bd-ship

   ## Changes
   <bullet list derived from commit messages on the branch>

   ## Risk
   <one paragraph — what could break, what you checked; if hold, explain why>

   ## Test plan
   - [x] Local tests passed (bd-ship gate)
   - [ ] CI green
   - [ ] (hold only) Human review

   ---
   Generated via bd-ship
   ```

9. **Create the PR.** Run:

   ```bash
   gh pr create --head "$BRANCH" --base main \
     --title "<title>" \
     --body "$(cat <<'EOF'
   <body>
   EOF
   )"
   ```

10. **Output contract** — on the final two lines of your response, print exactly:

   ```
   PR_NUMBER=<number>
   HOLD=<true|false>
   ```

   bd-ship.sh parses these lines to log the event and decide whether to merge immediately.
   Do not add any prefix, suffix, or markdown around them.

## Guardrails

- Never merge the PR yourself. bd-ship handles the merge after PR creation.
- Never run `gh pr merge`, `gh pr close`, or any write op other than `gh pr create`.
- Never push new commits to the branch — that was bd-ship's responsibility and is already done.
- Never compare the branch to local `main`; stale local main is a known source of empty or wrong PR diffs.
- If `bd show` or `git` fails, exit with an explanatory one-line error and no `PR_NUMBER` line.
- Do NOT invent issue IDs, file paths, or commit messages. Only use what the tools return.
- If the branch is ahead of main by zero commits, print `PR_NUMBER=null` and `HOLD=false` and stop.
