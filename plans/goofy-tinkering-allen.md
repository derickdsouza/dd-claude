# Plan: `pm` Environment Context CLI

## Context

The portfolio-manager project has 4 well-defined environments (`local`, `dev`, `uat`, `prod`) with per-env `.env` files, compose overlays, and deploy scripts — but no unified way to switch context between them. Today, each script takes env as an explicit argument, `.envrc` always loads `.env` (local), and cross-env operations require manual SSH/sourcing. The user works on one env at a time (occasionally two tabs) and needs both local env switching and remote operations (SSH, logs, DB, deploy). An AI agent will be the primary invoker, so the CLI must be self-describing and discoverable via `--help`.

## Approach

Single shell script CLI — a `scripts/pm` dispatcher routing to per-command files in `scripts/pm-commands/`. Pure bash, <5ms startup, native TTY passthrough, wraps existing scripts directly.

## File Structure

```
scripts/
  pm                              # Main dispatcher (chmod +x, added to PATH via direnv)
  pm-commands/
    _config.sh                    # Shared env registry — port table, SSH hosts, file mappings
    env.sh                        # pm env / pm use <env>
    db.sh                         # pm db
    logs.sh                       # pm logs [service]
    status.sh                     # pm status
    deploy.sh                     # pm deploy <env>
    restart.sh                    # pm restart <service>
    ssh.sh                        # pm ssh
    exec.sh                       # pm exec <service> <cmd>
```

## Critical Files to Modify

- `scripts/compose.sh` — fix `prod` → `production` overlay mapping (line 70 bug)
- `.envrc` — replace `dotenv` with `.pm-active-env`-aware loader
- `.gitignore` — add `.pm-active-env`
- `CLAUDE.md` — add `pm` CLI section for agent discovery
- `AGENTS.md` (if exists, else section in CLAUDE.md) — agent instructions for using `pm`

## Implementation Steps

### Step 1: Create `scripts/pm-commands/_config.sh` (~60 lines)

Shared env registry. Single source of truth for all env-specific values:

- **Env file mapping**: `local` → `.env`, `dev` → `.env.dev`, `uat` → `.env.uat`, `prod` → `.env.production`
- **Compose overlay mapping**: `local` → none, `dev` → `podman-compose.dev.yml`, `uat` → `podman-compose.uat.yml`, `prod` → `podman-compose.production.yml`
- **Port table**: API ports (`local:3001`, `dev:53001`, `uat:53002`, `prod:53003`), DB ports (`local:55432`, `dev:55433`)
- **SSH targets**: `dev` → `root@pm.global-fx.in`, `uat`/`prod` → configurable (empty = not set up yet)
- **Helper functions**: `get_env_file()`, `get_compose_overlay()`, `get_ssh_target()`, `get_db_name()`, `get_container_prefix()`, `is_remote()`, `require_confirmation()`, `color_for_env()`
- **Reuse existing values** from `packages/shared/src/environment.ts` (`getDbName` pattern: `portfolio_manager_${env}`, prefix: `pm-${env}`)

### Step 2: Create `scripts/pm` main dispatcher (~100 lines)

- Parse first arg as subcommand, delegate to `scripts/pm-commands/<cmd>.sh`
- Resolve active env: `$APP_ENV` → `$PM_ENV` → read `.pm-active-env` → default `local`
- Export `PM_ACTIVE_ENV` and `PM_PROJECT_DIR` for subcommands
- `pm --help` shows full command reference with natural-language descriptions and intent mapping
- `pm` with no args shows help + current env banner
- `pm --version` shows version

### Step 3: Create `scripts/pm-commands/env.sh` (~80 lines)

**`pm env`** — show active env details:
- Name (colorized), env file path, compose overlay, DB name, API port, SSH target, container prefix
- `pm env --json` — structured JSON output for agent consumption

**`pm use <env>`** — switch active env:
- Validate env name against `local|dev|uat|prod`
- Write to `.pm-active-env`
- Output `export APP_ENV=<env>` statements for eval
- If running interactively, also run `direnv allow` to trigger reload
- Print confirmation: "Switched to dev environment"

### Step 4: Fix `scripts/compose.sh` prod mapping (~5 lines changed)

Replace line 70's `podman-compose.${TARGET_ENV}.yml` with a lookup:
```bash
case "$TARGET_ENV" in
  prod) OVERLAY_NAME="production" ;;
  *)    OVERLAY_NAME="$TARGET_ENV" ;;
esac
OVERLAY="$PROJECT_DIR/podman-compose.${OVERLAY_NAME}.yml"
```

Also fix `.env` file mapping (line 44-47) to use `prod` → `.env.production`.

### Step 5: Create `scripts/pm-commands/status.sh` (~50 lines)

- For local: `podman ps -a --filter name=pm- --format 'table ...'`
- For remote: `ssh $target "podman ps -a --filter name=pm-${env} --format 'table ...'"`
- Also hit health endpoint: `curl -sf http://localhost:${api_port}/health`
- `--json` flag for structured output
- Show colorized env banner at top

### Step 6: Create `scripts/pm-commands/db.sh` (~50 lines)

- For local: `exec psql -h localhost -p ${db_port} -U pm_user -d ${db_name}`
- For remote: `exec ssh $target "podman exec -it pm-${env}-postgres psql -U pm_user -d ${db_name}"`
- `--help` explains which DB it connects to

### Step 7: Create `scripts/pm-commands/logs.sh` (~40 lines)

- Default service: `api`
- Resolve container: `pm-${env}-${service}` (local uses `pm-${service}` for base containers)
- For local: `exec podman logs --tail ${lines} -f ${container}`
- For remote: `exec ssh $target "podman logs --tail ${lines} -f ${container}"`
- `--lines N` flag (default 100)

### Step 8: Create `scripts/pm-commands/deploy.sh` (~40 lines)

- Requires explicit env argument (no default)
- For dev: `ssh $target "cd /opt/portfolio-manager && bash scripts/deploy-hostinger.sh"`
- For uat/prod: delegates to existing `scripts/deploy.sh`
- Prod/uat require `--confirm` flag or interactive typed confirmation
- `--build` flag passed through

### Step 9: Create `scripts/pm-commands/restart.sh` (~40 lines)

- Requires service argument
- Routes through `scripts/compose.sh ${env} restart ${service}`
- For remote: wraps in SSH
- Prod requires `--confirm`

### Step 10: Create `scripts/pm-commands/ssh.sh` (~25 lines)

- Map env to SSH target from `_config.sh`
- `exec ssh -i ~/.ssh/id_ed25519 ${ssh_target}`
- For local: print error "local environment has no remote server"
- `--cmd "..."` flag to run a single command instead of interactive shell

### Step 11: Create `scripts/pm-commands/exec.sh` (~35 lines)

- Requires service + command arguments
- Resolve container: `pm-${env}-${service}`
- For local: `exec podman exec -it ${container} ${cmd}`
- For remote: `exec ssh $target "podman exec -it ${container} ${cmd}"`

### Step 12: Update `.envrc` (~10 lines)

Replace current `dotenv` with:
```bash
PM_ACTIVE_ENV=$(cat .pm-active-env 2>/dev/null || echo "local")
case "$PM_ACTIVE_ENV" in
  local) dotenv ;;
  dev)   dotenv .env.dev ;;
  uat)   dotenv .env.uat ;;
  prod)  dotenv .env.production ;;
esac
export APP_ENV="$PM_ACTIVE_ENV"
PATH_add scripts
```

### Step 13: Update `.gitignore`

Add `.pm-active-env` to the env files section.

### Step 14: Update `CLAUDE.md` — Agent CLI Reference

Add a new section:

```markdown
## Environment CLI (`pm`)

The `pm` CLI manages environment context switching and cross-env operations.
Agents MUST use this CLI for all environment operations instead of manual SSH/env sourcing.

### Discovery
- `pm --help` — full command reference with intent mapping
- `pm <cmd> --help` — detailed help for any command
- `pm env --json` — machine-readable active env config

### Common Agent Operations
- Switch env: `eval $(pm use dev)`
- Check current env: `pm env`
- Query database: `pm db` (opens interactive psql)
- Check health: `pm status`
- View logs: `pm logs api --lines 50`
- Deploy: `pm deploy dev --confirm`
- Run migration: `pm exec api bun run db:migrate`
- SSH to server: `pm ssh`

### Safety
- Prod operations require `--confirm` flag
- Non-interactive mode (agent): always pass `--confirm` for prod/uat destructive operations
```

## Verification

1. `pm --help` prints full command reference
2. `pm use dev` + `pm env` shows dev as active
3. `pm use local` + `pm env` shows local as active
4. `pm status` shows running containers for active env
5. `pm db` opens psql to the correct database
6. `pm logs api` tails API logs
7. `scripts/compose.sh prod ps` no longer fails on missing overlay file
8. New shell tab picks up active env from `.pm-active-env` via direnv
9. `pm deploy prod` without `--confirm` is rejected
10. `pm ssh` when env=local prints helpful error
