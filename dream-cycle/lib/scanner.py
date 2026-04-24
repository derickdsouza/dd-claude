"""Scan memory directories and extract structured items for clustering."""
import re
from datetime import datetime
from pathlib import Path

from .config import memory_sources, SCOPE_GLOBAL, SCOPE_STACK, STACK_KEYWORDS
from .cluster import tokenize


_FRONTMATTER_RE = re.compile(r"^---\s*\n(.*?)\n---\s*\n", re.DOTALL)


def parse_frontmatter(text: str) -> tuple[dict, str]:
    m = _FRONTMATTER_RE.match(text)
    if not m:
        return {}, text
    meta = {}
    for line in m.group(1).splitlines():
        if ":" in line:
            k, _, v = line.partition(":")
            meta[k.strip()] = v.strip().strip("'\"")
    return meta, text[m.end():]


def detect_tags(text: str) -> list[str]:
    """Detect tech stack tags from content using keyword matching."""
    lower = text.lower()
    tags = set()
    for keyword, tag in STACK_KEYWORDS.items():
        if keyword in lower:
            tags.add(tag)
    return sorted(tags)


def scan_memory() -> list[dict]:
    """Walk all memory sources and return items with scope, project, and tags."""
    items = []
    seen_paths = set()

    for src_dir, scope, project_name in memory_sources():
        for md_file in sorted(src_dir.glob("*.md")):
            if md_file.name in ("MEMORY.md", "LESSONS.md"):
                continue
            if md_file in seen_paths:
                continue
            seen_paths.add(md_file)

            text = md_file.read_text(encoding="utf-8", errors="replace")
            meta, body = parse_frontmatter(text)

            name = meta.get("name", md_file.stem)
            mem_type = meta.get("type", "unknown")
            description = meta.get("description", "")

            content = body.strip()
            if not content and not description:
                continue

            combined = f"{name} {description} {content}"
            tokens = tokenize(combined)
            if not tokens:
                continue

            tags = detect_tags(combined)
            item_scope = scope
            # Promote to stack-scope if item has tech tags but is global
            if scope == SCOPE_GLOBAL and tags:
                item_scope = SCOPE_STACK

            items.append({
                "id": md_file.stem,
                "name": name,
                "type": mem_type,
                "description": description,
                "content": content[:500],
                "tokens": tokens,
                "source_path": str(md_file),
                "scope": item_scope,
                "project": project_name,
                "tags": tags,
                "scanned_at": datetime.utcnow().isoformat(),
            })

    return items
