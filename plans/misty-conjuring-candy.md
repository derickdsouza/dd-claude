# Plan: Historical Backtest Pipeline

## Context

The SelectAI inference job currently requires a live WebSocket market data feed for symbol lists and close prices. A backtest from April 1 2026 to today requires replaying the full pipeline — 12:15 and 15:15 inference bars plus continuous stop-loss monitoring — against historical data already in the database (`candles_eod`, `cumulative_candles`, `ticks`). The inference job uses port-injected adapters (`InferenceJobDeps`), making it straightforward to swap live adapters for DB-backed ones.

## Outcome

A standalone script `scripts/backtest/run-backtest.ts` (run via `bun`) that:
1. Verifies historical data completeness for the date range
2. Resets all trading state (FK-ordered) and seeds starting capital
3. Iterates NSE trading days, running stop-loss tick replay + inference + fill simulation
4. Writes all output to the same tables the live system uses (transactions, holdings_cache, ledger_entries, orms_signals, ems_orders, etc.)

## Delivery: Beads Epic + 15 Sub-Issues

The implementation plan will be captured in Beads as one epic with 15 atomic child issues, each tagged with the appropriate model.

---

## Confirmed APIs (from code verification)

| Need | API | File |
|------|-----|------|
| Simulate fill | `processOrderUpdate(id, { filledQuantity, fillPrice })` | `ems/fill-manager.service.ts` |
| Capital seed | `createDeposit(accountId, amount, effectiveAt, notes?)` | `services/ledger/ledger.service.ts` |
| Clear in-memory rules | `clearAllRules()` — already exported | `orms/risk/stop-loss-monitor.service.ts` |
| Flush HWM to DB | `flushDirtyHwm()` — already exported | same |
| Load rules from DB | `loadRulesFromDb()` — already exported | same |
| Check stop loss | `checkStopLoss(accountId, symbol, price)` | same |
| Trigger risk exit | `triggerRiskExit(request)` | `orms/risk/exit-trigger.service.ts` |
| Bar time → UTC ISO | `barTimeToISO(barTime)` — needs optional `dateStr` added | `lib/ist-timezone.ts` |

## FK Deletion Order (state reset)

```
ml_feedback_logs → pending_lf_entries → ems_order_events → ems_orders
→ approval_requests → orms_signals (orms_signal_events auto-CASCADE)
→ holdings_cache_audit → holdings_cache → rotation_rankings
→ selectai_probability_history → ledger_lots → ledger_entries
→ orms_stop_loss_rules → orms_drawdown_peaks → transactions
→ valuation_history → portfolio_metrics
→ INSERT ledger_entries DEPOSIT (createDeposit per active account)
```

## Issue List (15 issues across 3 groups)

### Group A — Discovery (haiku, P1)
1. Audit `MarketDataSourcePort` + `SelectAIGatewayPort` — list all required methods
2. Audit `getRotationRunner()` exact export path in `rotation/index.ts`
3. Audit `orms_global_config` upsert function for setting `globalMode = 'automatic'`

### Group B — Production code change (sonnet, P2)
4. Extend `barTimeToISO(barTime, dateStr?)` with optional historical date param

### Group C — Script files (haiku/sonnet/opus, P2–P3)
5. `lib/trading-days.ts` — getTradingDays from candles_eod (haiku)
6. `lib/verify-coverage.ts` — 4-check data completeness verifier (sonnet)
7. `lib/state-reset.ts` — FK-ordered reset + DEPOSIT seed (sonnet)
8. `lib/market-data-adapter.ts` — BacktestMarketDataAdapter (sonnet)
9. `lib/backtest-adapters.ts` — RunLock, AlertSink, SelectAIGateway, PositionContext (sonnet)
10. `lib/inference-factory.ts` — createBacktestInferenceJob() wiring (sonnet)
11. `lib/fill-simulator.ts` — fillAllPendingOrders + simulateStopLossFill (sonnet)
12. `lib/stop-loss-replay.ts` — replayStopLossForDay with tick + EOD fallback (sonnet)
13. `lib/backtest-day.ts` — runDay() full orchestration (opus)
14. `run-backtest.ts` — CLI entry point with arg parsing + day loop (sonnet)

### Group D — Verification
15. Dry-run E2E test: run script with --dry-run --skip-reset against dev DB, confirm no writes (sonnet)

## Critical Files

- `packages/backend/src/lib/ist-timezone.ts` — barTimeToISO to extend
- `packages/backend/src/services/selectai/inference-job/factory.ts` — createInferenceJob
- `packages/backend/src/services/selectai/inference-job/ports.ts` — port interfaces
- `packages/backend/src/services/orms/risk/stop-loss-monitor.service.ts` — checkStopLoss, clearAllRules, etc.
- `packages/backend/src/services/ems/fill-manager.service.ts` — processOrderUpdate
- `packages/backend/src/services/ledger/ledger.service.ts` — createDeposit
- `packages/backend/src/db/schema/*.ts` — all referenced tables
