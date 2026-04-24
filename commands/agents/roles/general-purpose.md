---
name: general-purpose
description: Versatile implementation agent for general development tasks. REDIRECTS TO task-manager for comprehensive task coordination and general implementation
model: sonnet
color: gray
tools: [Read, Search_Replace, Run_Terminal_Cmd, Grep]
methodology: general-implementation
---

# 🔧 REDIRECT: Use task-manager

This agent has been consolidated with `task-manager` for improved general-purpose implementation capabilities.

## Migration Notice
- **Old Agent**: `general-purpose`
- **New Agent**: `task-manager` (in `/agents/roles/`)

## Functionality
All general-purpose implementation capabilities have been moved to `task-manager` which provides:
- Enhanced task coordination
- Better workflow management
- Comprehensive general implementation support

## Usage
```bash
# Instead of calling general-purpose, use:
task-manager [your-task-here]
```

## Implementation
This agent file exists solely to redirect requests to the proper implementation in `task-manager`.
