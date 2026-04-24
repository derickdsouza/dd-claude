# Container Runtime: Podman

## CRITICAL: Use Podman Instead of Docker

Always use **Podman** instead of Docker Desktop for container operations.

---

## Command Mapping

| Docker Command | Podman Equivalent |
|----------------|-------------------|
| `docker ps` | `podman ps` |
| `docker run` | `podman run` |
| `docker build` | `podman build` |
| `docker images` | `podman images` |
| `docker pull` | `podman pull` |

---

## Starting the Podman Machine

```bash
# Start Podman machine (if not running)
podman machine start

# Check Podman status
podman machine info
podman ps
```

---

## Testcontainers/.NET Integration Tests

- Ensure Podman machine is running before running integration tests
- Set environment variable if needed: `export TESTCONTAINERS_RYUK_DISABLED=true`
- Testcontainers should auto-detect Podman via the Docker socket

---

## Podman Socket Location (macOS)

```bash
# Default socket path
/Users/$USER/.local/share/containers/podman/machine/podman.sock
```

---

## Common Examples

```bash
# Start Podman machine
podman machine start

# List running containers
podman ps

# Run a container
podman run -d --name mycontainer nginx

# Build an image
podman build -t myimage .

# Stop Podman machine when done
podman machine stop
```

---

## HTTPS Everywhere

All container deployments **MUST** use HTTPS. HTTP-only container setups are not supported.

- **Frontend (Vite)**: reads PEM certs from `/certs/cert.pem` + `/certs/key.pem`
- **Backend (Kestrel)**: reads PFX cert from `/certs/cert.pfx` (password: `devcert`)
- **Cookies**: always set `Secure = true` — requires HTTPS in all environments
- **Certs location**: `docker-compose/dev/certs/` (gitignored)
- **Generation**: `mkcert` for dev (trusted by system), proper CA certs for production

See `docs/developer-guides/containers.md` for the full TLS setup guide.

---

## Enforcement

- **NEVER** use `docker` commands
- **ALWAYS** use `podman` equivalents
- **NEVER** deploy containers over HTTP — always mount TLS certs
- If you accidentally use docker, immediately correct to podman
