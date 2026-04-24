"""Dream cycle configuration and path constants."""
from pathlib import Path

HOME = Path.home()
CLAUDE_DIR = HOME / ".claude"
DREAM_DIR = CLAUDE_DIR / "dream-cycle"
DATA_DIR = DREAM_DIR / "data"
MEMORY_DIR = CLAUDE_DIR / "memory"
PROJECTS_DIR = CLAUDE_DIR / "projects"

LESSONS_JSONL = DATA_DIR / "lessons.jsonl"
CANDIDATES_JSONL = DATA_DIR / "candidates.jsonl"
DECISIONS_JSONL = DATA_DIR / "decisions.jsonl"
EPISODES_JSONL = DATA_DIR / "episodes.jsonl"
LESSONS_MD = MEMORY_DIR / "LESSONS.md"

JACCARD_THRESHOLD = 0.30
MIN_CLUSTER_SIZE = 2
MIN_CONTENT_WORDS = 3
DECAY_DAYS = 90

SCOPE_GLOBAL = "global"
SCOPE_STACK = "stack"
SCOPE_PROJECT = "project"

STOP_WORDS = frozenset({
    "the", "and", "for", "are", "but", "not", "you", "all", "can",
    "her", "was", "one", "our", "out", "has", "had", "his", "how",
    "its", "may", "new", "now", "old", "see", "way", "who", "did",
    "get", "got", "let", "say", "she", "too", "use", "via", "any",
})

STACK_KEYWORDS = {
    "bun": "bun",
    "podman": "podman",
    "docker": "podman",
    "container": "podman",
    "hono": "hono",
    "drizzle": "drizzle",
    "postgresql": "postgresql",
    "postgres": "postgresql",
    "redis": "redis",
    "bullmq": "bullmq",
    "react": "react",
    "vite": "vite",
    "tailwind": "tailwindcss",
    "tailwindcss": "tailwindcss",
    "zod": "zod",
    "typescript": "typescript",
    "zerodha": "zerodha",
    "kite": "kite",
    "tradex": "tradex",
    "selectai": "selectai",
    "duckdb": "duckdb",
    "nse": "nse",
    "hostinger": "hostinger",
    "ufw": "ufw",
    "iptables": "iptables",
}


def _path_to_raw(path: Path) -> str:
    """Encode a filesystem path to .claude/projects/ dir name format.

    E.g. /Users/derickdsouza/Projects/development/portfolio-manager
         → '-Users-derickdsouza-Projects-development-portfolio-manager'
    """
    return "-" + str(path).replace("/", "-")


def _clean_project_name(raw_name: str) -> str:
    """Derive human-readable project name from .claude/projects/ dir name.

    Extracts the last path component by matching against known dirs on disk,
    falling back to the last meaningful segment of the encoded name.
    """
    # Try to find the actual path on disk by testing different split points
    parts = raw_name.lstrip("-").split("-")
    # Try progressively shorter prefixes until we find an existing path
    for i in range(len(parts)):
        candidate = Path("/" + "/".join(parts[:len(parts) - i]))
        if candidate.exists() and candidate.is_dir():
            # The remaining segments form the project name
            remaining = "-".join(parts[len(parts) - i:])
            if remaining:
                return remaining
            return candidate.name
    return parts[-1] if parts else raw_name


def ensure_dirs():
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    MEMORY_DIR.mkdir(parents=True, exist_ok=True)


def memory_sources() -> list[tuple[Path, str, str]]:
    """Return (directory, scope, project_name) tuples for all memory sources."""
    sources = []
    if MEMORY_DIR.exists():
        sources.append((MEMORY_DIR, SCOPE_GLOBAL, ""))
    if PROJECTS_DIR.exists():
        for p in PROJECTS_DIR.iterdir():
            mem = p / "memory"
            if mem.is_dir():
                project_name = _clean_project_name(p.name)
                sources.append((mem, SCOPE_PROJECT, project_name))
    return sources


def find_project_dir(project_name: str) -> Path | None:
    """Find the .claude/projects/<raw>/ dir for a clean project name.

    Matches by encoding the project name as a suffix of the raw dir name,
    then validates that the reconstructed path exists on disk.
    """
    if not PROJECTS_DIR.exists():
        return None
    matches = []
    for p in PROJECTS_DIR.iterdir():
        mem = p / "memory"
        if not mem.is_dir():
            continue
        clean = _clean_project_name(p.name)
        if clean != project_name:
            continue
        # Check how many memory files exist (for disambiguation)
        mem_count = len(list(mem.glob("*.md"))) if mem.exists() else 0
        matches.append((mem_count, p))

    if not matches:
        return None
    matches.sort(key=lambda x: -x[0])
    return matches[0][1]


def resolve_project_from_cwd() -> tuple[str, Path | None]:
    """Determine which project the CWD belongs to.

    Encodes CWD path in the same format as .claude/projects/ dirs,
    then finds the matching project. Returns (clean_name, project_dir).
    """
    cwd = Path.cwd().resolve()
    if not PROJECTS_DIR.exists():
        return "", None

    cwd_encoded = _path_to_raw(cwd)

    # Check if any project dir name is a prefix of the encoded CWD
    # (handles CWD being inside a project)
    for p in PROJECTS_DIR.iterdir():
        mem = p / "memory"
        if not mem.is_dir():
            continue
        if cwd_encoded.startswith(p.name) or p.name.startswith(cwd_encoded):
            return _clean_project_name(p.name), p

    # Fallback: check if CWD itself matches a project dir
    for p in PROJECTS_DIR.iterdir():
        mem = p / "memory"
        if not mem.is_dir():
            continue
        if _path_to_raw(cwd) == p.name:
            return _clean_project_name(p.name), p

    return "", None
