---
name: prd-to-issues
description: "Break a PRD into vertical-slice beads issues ready for TDD implementation."
---

# PRD to Issues

Break a PRD into independently-grabbable beads issues using vertical slices (tracer bullets).

## Process

### 1. Locate the PRD

Ask the user for the PRD beads issue ID (or paste the content directly).

If the PRD is not already in your context window, fetch it with `bd show <id>`.

### 2. Explore the codebase (optional)

If you have not already explored the codebase, do so to understand the current state of the code.

### 3. Draft vertical slices

Break the PRD into **tracer bullet** issues. Each issue is a thin vertical slice that cuts through ALL integration layers end-to-end, NOT a horizontal slice of one layer.

Slices may be 'HITL' or 'AFK'. HITL slices require human interaction, such as an architectural decision or a design review. AFK slices can be implemented and merged without human interaction. Prefer AFK over HITL where possible.

<vertical-slice-rules>
- Each slice delivers a narrow but COMPLETE path through every layer (schema, API, UI, tests)
- A completed slice is demoable or verifiable on its own
- Prefer many thin slices over few thick ones
</vertical-slice-rules>

### 4. Quiz the user

Present the proposed breakdown as a numbered list. For each slice, show:

- **Title**: short descriptive name
- **Type**: HITL / AFK
- **Blocked by**: which other slices (if any) must complete first
- **User stories covered**: which user stories from the PRD this addresses

Ask the user:

- Does the granularity feel right? (too coarse / too fine)
- Are the dependency relationships correct?
- Should any slices be merged or split further?
- Are the correct slices marked as HITL and AFK?

Iterate until the user approves the breakdown.

### 5. Create the beads issues

For each approved slice, create a beads issue using `bd create`. Create in dependency order (blockers first) so you can reference real IDs in `--deps`.

```bash
# Create a child issue under the parent PRD epic
bd create "Slice title" \
  -d "Description of this vertical slice" \
  -t task \
  -p 2 \
  --parent <prd-epic-id> \
  --deps "blocks:<blocker-id>"
```

After creating, link dependent slices:

```bash
bd link <slice-id> <blocker-id> --type blocks
```

Do NOT close or modify the parent PRD issue.
