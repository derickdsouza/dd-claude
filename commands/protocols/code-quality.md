# Code Quality & ESLint Standards

## Import Management

Only import what you use in the file. Remove unused imports.

### Type Imports

Use type imports to avoid runtime overhead:

```typescript
// CORRECT
import type { Deal } from '@/types'

// WRONG - unless interface is used as value
import { Deal } from '@/types'
```

---

## Unused Variables & Parameters

When a variable or parameter is required for signature compatibility but not used, prefix with underscore:

```typescript
// WRONG
try {
  await something()
} catch (error) {
  // error never used
  console.log('Failed')
}

// CORRECT
try {
  await something()
} catch (_error) {
  // Explicitly indicate intentional ignoring
  console.log('Failed')
}
```

---

## Test File Best Practices

### Vitest Patterns

```typescript
// CORRECT
import { describe, it, expect, beforeEach } from 'vitest'
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'

describe('MyComponent', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
  })

  it('should work', () => {
    expect(true).toBe(true)
  })
})
```

### Playwright E2E Patterns

```typescript
// WRONG - test doesn't use page
test('describe test', async ({ page, context }) => {
  // Neither parameter is used
})

// CORRECT - only request what's needed
test('describe test', async () => {
  // No unused parameters
})
```

---

## Regular Expressions

Only escape characters that need escaping:

```typescript
// WRONG - unnecessary escapes
const regex = /[A-Z0-9\-]+/  // Hyphen doesn't need escape at end

// CORRECT
const regex = /[A-Z0-9-]+/  // Only escape when necessary
```

---

## Code Generation Guidelines

1. **Always use only the imports needed** - Don't import types or functions you don't use
2. **Prefix unused parameters with underscore** - Especially in catch blocks and test setup
3. **Use proper test imports** - Import test utilities from correct packages
4. **Type imports for types only** - Use `import type {}` when importing TypeScript types
5. **Fixture parameters** - In Playwright tests, only include fixtures used in test body
6. **MSW handlers** - Only import MSW utilities when actually defining handlers
7. **Use TypeScript strict mode for frontend work**
8. **Follow .NET coding standards for backend work**

---

## Build and Quality Gates

Before committing or completing tasks:

- All tests must pass before commits
- TypeScript compilation must succeed (0 errors)
- ESLint rules must pass (0 warnings, 0 errors)
- Follow conventional commit messages
- Implement proper error handling and logging

---

## Common Mistake Patterns to Avoid

| WRONG | CORRECT |
|-------|---------|
| Import but never use | Remove import or use the import |
| `catch (error)` but don't use error | `catch (_error)` to signal intentional |
| Test with unused setup variables | Remove variable or rename with `_` prefix |
| Unused fixture parameters | Remove from destructuring or rename to `_param` |
| Type imports as values | Use `import type {}` syntax |
| Unnecessary regex escapes | Only escape what truly needs escaping |
