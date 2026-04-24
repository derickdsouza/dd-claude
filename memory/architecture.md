# Architecture Decisions

Cross-project architecture learnings and design principles.

---

## Universal Principles

- Test through public interfaces, not implementation details
- Prefer deep modules: small interface, rich implementation (A Philosophy of Software Design)
- Vertical slices over horizontal layers for feature development
- Avoid speculative abstractions — implement what's needed now

## Dependency Injection

Accept dependencies, don't create them. Makes testing natural:
```typescript
// Good — testable
function processOrder(order, paymentGateway) {}

// Avoid — hard to test
function processOrder(order) {
  const gateway = new StripeGateway();
}
```

---

## Per-Project Decisions

See individual project CLAUDE.md and `docs/adr/` directories.

---

## Format

When adding a cross-project decision:
```
- [YYYY-MM-DD] <project or "global">: <decision and rationale>
```
