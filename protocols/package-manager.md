# Package Manager: Bun

## CRITICAL: NEVER Use npm or pnpm - Use Bun ONLY

**MANDATORY REQUIREMENT**: You MUST use **Bun** for ALL package management and script execution. Using npm or pnpm is PROHIBITED.

---

## Command Mapping

| npm/pnpm Command | Bun Equivalent |
|------------------|----------------|
| `npm install` | `bun install` |
| `npm add <pkg>` | `bun add <pkg>` |
| `npm remove <pkg>` | `bun remove <pkg>` |
| `npm run build` | `bun run build` |
| `npm run dev` | `bun run dev` |
| `npm run test` | `bun run test` |
| `npm outdated` | `bun outdated` |
| `npm update` | `bun update` |
| `npx <tool>` | `bunx <tool>` |

---

## Package Installation

```bash
# Install all dependencies
bun install

# Add a package
bun add vue-i18n

# Add a dev dependency
bun add -d vitest

# Remove a package
bun remove lodash
```

---

## Running Scripts

```bash
# Run scripts from package.json
bun run build
bun run dev
bun run test
bun run lint
```

---

## Direct Execution

Bun can run TypeScript/JavaScript directly:

```bash
bun script.ts
bun script.js
```

---

## npx-Style Execution

Use `bunx` instead of `npx`:

```bash
bunx vue-tsc --noEmit
bunx vite build
bunx eslint .
```

---

## Notes

- Bun uses `bun.lock` (or `bun.lockb`) for lock files
- Bun is compatible with `package.json` scripts
- Bun is significantly faster than npm/pnpm for most operations

---

## Enforcement

- **NEVER** suggest or use `npm` commands
- **NEVER** suggest or use `pnpm` commands
- **ALWAYS** use `bun` or `bunx` equivalents
- If you accidentally use npm/pnpm, immediately correct to bun
