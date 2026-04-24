# Graduated Lessons

Lessons extracted from patterns across memory files.
Managed by `~/.claude/dream-cycle/`. Edit above the sentinel; content below is auto-generated.

<!-- dream-cycle:auto-generated -->
<!-- 5 graduated lessons -->

## Universal

- **Always report time in IST, never UTC**
  - _Why: past timezone assumption incidents_
  - _Graduated: 2026-04-21_

## Tech Stack

- **Use lazy getLogger() inside functions, not at module scope**
  - _Why: Bun mock.module cannot replace already-captured bindings_
  - _Graduated: 2026-04-21 | Tags: bun_

## Project-Specific — portfolio-manager

- **UFW must allow UDP/TCP 53 per Podman network subnet**
  - _Why: missing rule caused container DNS ETIMEOUT_
  - _Graduated: 2026-04-21 | Tags: podman, ufw_

- **R134 targets processor.py (342 LOC) for division by zero in factor application, no phase isolation, lost tracebacks**
  - _Why: SelectAI processor robustness across 7 architecture rounds_
  - _Graduated: 2026-04-21 | Tags: duckdb, kite, nse, selectai_

- **R123 targets data-fetcher storage.py (1930 LOC) for DuckDB transaction safety, file locking, and resume reliability**
  - _Why: DuckDB transaction safety in data-fetcher across multiple storage rounds_
  - _Graduated: 2026-04-21 | Tags: duckdb, kite, nse, postgresql, selectai_

