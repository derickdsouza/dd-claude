---
name: write-a-prd
description: "Create a PRD through user interview and codebase exploration, submit as beads issue."
---

This skill will be invoked when the user wants to create a PRD. You may skip steps if you don't consider them necessary.

1. Ask the user for a long, detailed description of the problem they want to solve and any potential ideas for solutions.

2. Explore the repo to verify their assertions and understand the current state of the codebase.

3. Interview the user relentlessly about every aspect of this plan until you reach a shared understanding. Walk down each branch of the design tree, resolving dependencies between decisions one-by-one.

4. Sketch out the major modules you will need to build or modify to complete the implementation. Actively look for opportunities to extract deep modules that can be tested in isolation.

A deep module (as opposed to a shallow module) is one which encapsulates a lot of functionality in a simple, testable interface which rarely changes.

Check with the user that these modules match their expectations. Check with the user which modules they want tests written for.

5. Once you have a complete understanding of the problem and solution, create the PRD as a beads epic:

```bash
bd create "PRD: <feature name>" \
  -d "$(cat <<'EOF'
## Problem Statement

<problem from user's perspective>

## Solution

<solution from user's perspective>

## User Stories

1. As a <actor>, I want <feature>, so that <benefit>
2. ...

## Implementation Decisions

- Modules to build/modify
- Interface changes
- Architectural decisions
- Schema changes
- API contracts

## Testing Decisions

- What makes a good test for this feature
- Which modules will be tested
- Prior art in the codebase

## Out of Scope

<what is explicitly not included>

## Further Notes

<any additional notes>
EOF
)" \
  -t epic \
  -p 2
```
