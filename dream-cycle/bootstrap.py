#!/usr/bin/env python3
"""Bootstrap dream-cycle for a project — new or existing.

Creates memory dir, seeds LESSONS.md, writes metadata.

Usage:
    # Auto-detect from CWD
    python3 ~/.claude/dream-cycle/bootstrap.py

    # Explicit project name
    python3 ~/.claude/dream-cycle/bootstrap.py portfolio-manager --tags bun,podman,hono

    # Force re-initialize
    python3 ~/.claude/dream-cycle/bootstrap.py portfolio-manager --tags bun,podman,hono --force

    # Dry run
    python3 ~/.claude/dream-cycle/bootstrap.py --dry-run
"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from lib.config import (
    ensure_dirs, find_project_dir, resolve_project_from_cwd,
    LESSONS_JSONL, CANDIDATES_JSONL,
)
from lib.state import read_jsonl, now_iso, atomic_write
from lib.render import render_lessons


def bootstrap(project_name: str, tags: list[str], force: bool, dry_run: bool) -> int:
    ensure_dirs()

    project_dir = find_project_dir(project_name)
    if not project_dir:
        print(f"[bootstrap] Project '{project_name}' not found in ~/.claude/projects/")
        print(f"[bootstrap] Start Claude Code in the repo first, then re-run bootstrap.")
        return 1

    memory_dir = project_dir / "memory"
    lessons_file = memory_dir / "LESSONS.md"
    meta_file = memory_dir / ".dream-meta.json"

    existing_meta = {}
    if meta_file.exists():
        try:
            existing_meta = json.loads(meta_file.read_text())
        except (json.JSONDecodeError, OSError):
            pass

    if existing_meta.get("bootstrapped") and not force:
        print(f"[bootstrap] '{project_name}' already bootstrapped ({existing_meta.get('bootstrapped_at', 'unknown')[:10]})")
        print(f"[bootstrap] Use --force to re-initialize.")
        return 0

    if dry_run:
        print(f"[bootstrap:dry-run] Would initialize '{project_name}':")
        print(f"  Project dir:  {project_dir}")
        print(f"  Memory dir:   {memory_dir}")
        print(f"  LESSONS.md:   {lessons_file}")
        print(f"  Tags:         {', '.join(tags) if tags else '(none)'}")
        print(f"  Force:        {force}")
        return 0

    memory_dir.mkdir(parents=True, exist_ok=True)

    global_count = len(read_jsonl(LESSONS_JSONL))
    project_lessons = [l for l in read_jsonl(LESSONS_JSONL)
                       if l.get("project") == project_name]

    if not lessons_file.exists() or force:
        lines = [
            f"# Graduated Lessons — {project_name}",
            "",
            f"Auto-generated from dream-cycle. Global + stack + this project's lessons.",
            "",
        ]
        if global_count > 0:
            lines.append(f"<!-- {global_count} global/stack lessons available (rendered on next dream cycle) -->")
            lines.append("")
        if project_lessons:
            lines.append("## Project-Specific Lessons")
            lines.append("")
            for l in project_lessons:
                claim = l.get("claim", "")
                rationale = l.get("rationale", "")
                entry = f"- **{claim}**"
                if rationale:
                    entry += f"\n  - _Why: {rationale}_"
                lines.append(entry)
                lines.append("")
        atomic_write(lessons_file, "\n".join(lines) + "\n")
        print(f"[bootstrap] Created {lessons_file}")
    else:
        print(f"[bootstrap] Preserved existing {lessons_file}")

    meta = {
        "project": project_name,
        "tags": tags,
        "bootstrapped": True,
        "bootstrapped_at": now_iso(),
        "memory_dir": str(memory_dir),
        "dream_cycle_version": "1.0.0",
    }
    atomic_write(meta_file, json.dumps(meta, indent=2) + "\n")
    print(f"[bootstrap] Wrote {meta_file}")

    mem_files = [f for f in memory_dir.glob("*.md")
                 if f.name not in ("MEMORY.md", "LESSONS.md")]
    candidates = len([c for c in read_jsonl(CANDIDATES_JSONL)
                      if c.get("project") == project_name and c.get("status") == "staged"])

    print(f"\n[bootstrap] '{project_name}' initialized:")
    print(f"  Memory files:   {len(mem_files)}")
    print(f"  Tags:           {', '.join(tags) if tags else '(none)'}")
    print(f"  Graduated:      {len(project_lessons)}")
    print(f"  Pending:        {candidates}")
    print(f"  Global lessons: {global_count}")

    total = render_lessons()
    print(f"\n[bootstrap] Re-rendered LESSONS.md ({total} total lessons across all scopes)")
    print(f"[bootstrap] Next cron run at 03:00 will dream on {len(mem_files)} memory files")
    return 0


def main():
    parser = argparse.ArgumentParser(description="Bootstrap dream-cycle for a project")
    parser.add_argument("project", nargs="?", default="",
                        help="Project name (auto-detected from CWD if omitted)")
    parser.add_argument("--tags", "-t", default="",
                        help="Comma-separated tech stack tags (e.g. bun,podman,hono)")
    parser.add_argument("--force", "-f", action="store_true",
                        help="Re-initialize even if already bootstrapped")
    parser.add_argument("--dry-run", action="store_true",
                        help="Show what would happen without making changes")
    args = parser.parse_args()

    project = args.project
    if not project:
        name, _ = resolve_project_from_cwd()
        if name:
            project = name
        else:
            project = Path.cwd().name
            print(f"[bootstrap] Auto-detected project from CWD: '{project}'")

    tags = [t.strip() for t in args.tags.split(",") if t.strip()] if args.tags else []
    return bootstrap(project, tags, args.force, args.dry_run)


if __name__ == "__main__":
    sys.exit(main())
