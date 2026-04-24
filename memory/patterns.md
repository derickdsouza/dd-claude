# Coding Patterns

Cross-project implementation patterns and conventions.

---

## Established Patterns

- [2026-04-20] tooling: In `set -euo pipefail` shell scripts, optional extraction pipelines like `grep '^KEY=' file | tail -1 | cut -d= -f2` must end with `|| true` or be wrapped in conditional logic. Otherwise a missing match aborts the script before the intended validation/error branch can run.
- [2026-04-20] tooling: Beads/ship automation must fail closed. If GitButler branch ownership is ambiguous, the worktree contains unrelated applied/unassigned changes, or PR creation fails, abort and keep the bead open instead of guessing a branch or relying on manual `gh pr create`/`bd close` recovery. Prefer the repo's declared test script (`bun run test --run` when `package.json` defines `test`) over ad hoc test command guesses.
- [2026-04-20] tooling: Approval automation for GitHub's `require_last_push_approval` rule must choose the reviewer from the last pusher, not the PR opener. In a two-account setup, skip when the only legal reviewer would self-approve or when the last pusher is outside the configured pair.
- [2026-04-20] tooling: If a ship gate fails on files outside the current bead diff, treat it as workspace contamination or an ownership bug, not as permission to edit foreign files. Worker prompts should explicitly tell agents to re-read after edit-state errors instead of stacking search/replace guesses.
- [2026-04-19] tooling: GitButler mutation examples must use `rm -f .git/*.lock 2>/dev/null; but ... --status-after`, not `&&`, because zsh `nomatch` aborts the command when no lock files exist. Treat stale `.git/*.lock` cleanup as automatic preflight, not a manual exception.
- [2026-04-17] adr005-removal: When removing ADR-005 violations (portfolio-level aggregations), follow: (1) delete function + helper key fn; (2) fix `loadFromDb` to skip+warn stale scope_type='portfolio' rows (include row id in warn object); (3) remove from port interface + adapter; (4) route schema change: make `accountId: z.string()` (not optional); (5) update orchestrator test mock to not include removed method; (6) file P1 follow-up bead for DB purge migration. Lazy `getLogger()` inside functions (not at module scope) — required for Bun mock.module compatibility.

- [2026-04-17] tick-validation-parity: Hot-path tick validators (`isValidTradexTick`) must use `Number.isFinite(v) && v > 0` — not just `v < 0` — to reject NaN and Infinity. Mirror Kite's guard pattern field-by-field (lastPrice, volume, ohlc.*). Export the validator for test coverage. Zod schema (`marketDataTickSchema`) lives in `packages/shared/src/schemas/market-data.ts` for boundary use only (Redis publish, worker dequeue), NOT on the hot-path emit.

- [2026-04-17] staleness-guard-dep-injection: Never read `getEnv()` inside a hot-path handler (`handlePriceUpdate`) — Bun shares module registry between test files in the same run, so other files' `mock.module('lib/env')` calls will replace the real module. Pass thresholds as injected deps with env-sourced defaults in the production singleton (e.g. `stalePriceThresholdMs?: number` on `RiskOrchestratorDeps`, defaulting to `5_000` in the factory destructuring, read from `getEnv()` only in `singleton.ts`).
- [2026-04-17] tick-pipeline-probe: Inject `{ now: () => number, getLastEvaluationAt: () => number | null }` into probes — avoids patching globals; module state (`_lastEvaluationAt`) + `recordEvaluationTimestamp()` + `getLastEvaluationAt()` kept in the probe file; `evaluateExitRulesForSymbol` imports `recordEvaluationTimestamp` and calls it at the top of the function body (before any early returns that skip work).
- [2026-04-17] sweeper-function-options-pattern: Expiry/cleanup sweepers take `options?: { maxAgeMs?: number }` with a module-level default constant (not a positional param) — makes callsites readable (`expireStaleValidating({ maxAgeMs: 30_000 })`) and the default self-documenting. Symmetric with sibling sweepers that use positional `timeoutMinutes` only where minutes is the natural unit. Metric increment (`metricsService.incrementCounter(...)`) is fire-and-forget (`.catch(() => {})`) inside the per-row try-block, after the successful `updateSignalStatus` call.
- [2026-04-17] freeze-gate-port: Inject a `FreezeGate` port into workflow factories rather than calling the freeze service directly. Port returns `{ frozen, allowExitsOnly }`. Production adapter delegates to `getFreezeStatus()`. Test stub (`StubFreezeGate`) exposes `.freeze(portfolioId, { allowExitsOnly })` / `.unfreeze()`. Transient status like `FROZEN` must NOT be added to the DB enum — add a separate `ResultStatus = PersistedStatus | 'FROZEN'` type in the public surface instead.
- [2026-04-17] queue-timeout-tracking: Bounded LRU Map for timed-out requestIds — keep a `TimedOutTracker` (Map<id, timestampMs> capped at 10k with oldest eviction) to distinguish "late response after timeout" (log INFO + metric) from "truly uncorrelated" (log WARN). Add requestId to tracker when timer fires; delete from tracker after consuming the late message.
- [2026-04-17] bun-mock-logger: Expose `mockLogInfo = mock(() => {})` etc. BEFORE `mock.module('../../lib/logger', ...)` so they are spyable. Filter `mock.calls` on `c[1].includes('keyword')` where c[0] is the data object and c[1] is the message string (pino signature).
- [2026-04-17] zod-validation: Shared canonical symbol schema lives in `packages/shared/src/schemas/symbol.ts` — `CANONICAL_SYMBOL_RE = /^[A-Z0-9&\-]+$/` + `canonicalSymbolSchema` enforces Zerodha form; import into any schema that takes a tradingsymbol at an inbound boundary
- [2026-04-17] testing: Capture pino logger output in Bun tests via `spyOn(pinoInstance, 'warn')` — first arg of `mock.calls[0]` is the log object, second is the message string
- [2026-04-17] architecture: Synthetic TradeX symbols follow `TOKEN_<EXCHANGE>_<token>` pattern; parse with `/^TOKEN_[A-Z]+_(\d+)$/` to extract numeric token for operator-readable error logs
- [2026-04-17] testing: Python IST naive-datetime bug: freeze at UTC 20:00 (= IST 01:30 next day), patch `get_last_trading_day`, assert end_date=IST-today passes. Fix: `datetime.now(_get_market_tz()).date()` for comparisons; `.replace(tzinfo=None)` to strip tz for naive anchor.
- [2026-04-17] bash-testing: Market-hours guard test seam — override `_get_ist_now()` as an exported bash function BEFORE sourcing `_config.sh`. Write env stub file to actual project root (script recomputes PROJECT_DIR from its own path; env override does not work). Override `sleep` as exported function to skip countdowns. Supply confirmation string via `<<< "$stdin_data"` heredoc so guard-blocked path is reached.
- [2026-04-17] ist-fy-boundary: Always use `toIST(date).month` (1-based) + `.year` for fiscal year calculations — never `date.getMonth()` (0-based, UTC). FY starts April 1 IST: `ist.month >= 4 ? ist.year : ist.year - 1`. Test the boundary with `setSystemTime(new Date('YYYY-03-31T18:45:00Z'))` (= IST April 1 00:15) and assert FY = next year.
- [2026-04-17] defensive-fallback-guard: When a fallback else-branch implicitly assumes non-empty input (e.g. `ticks[0].open`), add an explicit `if (input.length === 0)` guard that returns null + emits `getLogger().warn({ component, reason: 'xxx-blocked' }, msg)`. Decouple the freshness check from ohlc-presence so the outer null-return guard doesn't mask the bug — test by removing the ohlc check from freshness, setting ohlc=null in lastTick, empty ticks, and asserting no throw + warn emitted. Lazy `getLogger()` call inside guard body ensures Bun mock.module replacement is captured at call time.
- [2026-04-17] redis-backed-sequence: Replace in-process `let counter = 0` with `incrWithExpire(key, ttlSeconds)` from `lib/redis-atomic.ts`. Key format: `<service>:<epochSeconds>` (per-second key; Redis client auto-prefixes with `pm:${env}:`). TTL=10s keeps counters short-lived. Fall back to local counter in `catch` so availability is preserved when Redis is down — log `error` not `throw`. Return type changes from `number` to `Promise<number>`. Preserve existing function name and callers — just add `async/await` at call sites.
- [2026-04-17] ems-market-guard: Call `guardMarketOpen(orderId, 'market', 0, 1)` from `executor-utils` before `broker.placeOrder` on the direct market-algo path. Non-null return = market closed; update order to FAILED with `errorMessage: 'MARKET_CLOSED'` and return `{ orderId, status: 'FAILED', reason: 'MARKET_CLOSED' }`. Mock `executor-utils` as a full module in tests to control the guard's return value independently of `isMarketOpen`.
- [2026-04-17] drizzle-partial-unique-index: Partial unique index pattern in Drizzle v0.36 / pg-core: `uniqueIndex('name').on(table.col).where(sql\`col IS NOT NULL\`)` — sql tagged template from `'drizzle-orm'` (not pg-core). To introspect in tests: `getTableConfig(table).indexes.find(i => i.config.name === 'name')` — check `.config.unique === true` and `.config.where` is defined. Bun module-mock pollution: schema tests that call `getTableConfig` at describe-level must use `realModulePath` dynamic import to avoid receiving a mocked barrel object from sibling test files that call `mock.module('../../db/schema', ...)`.
- [2026-04-20] tooling: Multi-step slash-command workflows must persist session state by stable session key or TTY, not `$$`/`$PPID`. Agent allocation files keyed to shell PIDs break as soon as commands hop to a new shell process.
- [2026-04-20] tooling: For shell-generated worklists, never stuff a space-separated ID list into one variable and iterate after changing `IFS`. Write IDs newline-delimited to a temp file and read them with `while IFS= read -r id; do ...; done` to avoid accidental batch corruption.
- [2026-04-21] tooling: Customized `.beadswave/pre-ship.sh` hooks drift faster than wrappers. Lint them for raw `.git/*.lock` globs, bespoke `mktemp preship.XXXXXX` wrappers, and missing shared runtime usage so global shell fixes keep applying after local customization.

---

## Format

When adding an entry:
```
- [YYYY-MM-DD] <category>: <pattern description>
```

Categories: `testing` · `architecture` · `performance` · `security` · `tooling` · `tdd`

---

## TDD Patterns

- One test at a time — never write all tests before implementing
- Test through public interfaces, not internal state
- Mock only at system boundaries (external APIs, time, randomness)
- Prefer integration-style tests over unit tests for business logic
