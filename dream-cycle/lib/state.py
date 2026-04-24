"""JSONL state management with advisory file locking."""
import fcntl
import json
from datetime import datetime, timezone
from pathlib import Path


def read_jsonl(path: Path) -> list[dict]:
    if not path.exists():
        return []
    records = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    records.append(json.loads(line))
                except json.JSONDecodeError:
                    continue
    return records


def append_jsonl(path: Path, record: dict):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "a") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        f.write(json.dumps(record, ensure_ascii=False) + "\n")
        fcntl.flock(f, fcntl.LOCK_UN)


def rewrite_jsonl(path: Path, records: list[dict]):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    with open(tmp, "w") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        for r in records:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
        fcntl.flock(f, fcntl.LOCK_UN)
    tmp.replace(path)


def atomic_write(path: Path, content: str):
    tmp = path.with_suffix(".tmp")
    tmp.write_text(content, encoding="utf-8")
    tmp.replace(path)


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def pattern_id(claim: str, conditions: list[str]) -> str:
    """Canonical hash for a pattern — stable across cluster changes."""
    import hashlib
    parts = [claim.strip().casefold()]
    for c in sorted(set(conditions)):
        canonical = " ".join(c.lower().split())
        if canonical:
            parts.append(canonical)
    blob = "||".join(parts)
    return hashlib.sha256(blob.encode()).hexdigest()[:12]
