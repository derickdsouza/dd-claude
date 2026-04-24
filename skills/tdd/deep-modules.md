# Deep Modules

From "A Philosophy of Software Design" by John Ousterhout.

**Deep module** = small interface + lots of implementation (ideal)

```
┌─────────────────────┐
│  few methods        │  ← interface (narrow)
│  simple params      │
├─────────────────────┤
│                     │
│  complex logic      │  ← implementation (deep)
│                     │
└─────────────────────┘
```

**Shallow module** = many methods, complex params, little logic underneath (avoid)

## Design Questions

When designing an interface, ask:

- Can I reduce the number of methods?
- Can I simplify the parameters?
- Can I hide more logic internally?

The goal: minimize what callers need to know. Maximize what the module handles internally.
