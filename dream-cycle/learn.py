#!/usr/bin/env python3
"""One-shot lesson teaching: claim + rationale → graduated lesson.

Usage:
    python3 ~/.claude/dream-cycle/learn.py "Always serialize timestamps in UTC" --rationale "past cross-region bugs"
    python3 ~/.claude/dream-cycle/learn.py "Use lazy getLogger()" --rationale "Bun mock.module" --scope stack --tags bun
    python3 ~/.claude/dream-cycle/learn.py "Never deploy during market hours" --rationale "disrupted live trading" --scope project --project portfolio-manager
"""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from lib.config import ensure_dirs, LESSONS_JSONL, SCOPE_GLOBAL
from lib.state import read_jsonl, append_jsonl, now_iso, pattern_id
from lib.validate import validate
from lib.render import render_lessons


def main():
    parser = argparse.ArgumentParser(description="Teach a lesson in one step")
    parser.add_argument("claim", help="The lesson claim")
    parser.add_argument("--rationale", "-r", required=True, help="Why this lesson matters")
    parser.add_argument("--type", "-t", default="manual", help="Memory type tag")
    parser.add_argument("--source", "-s", default="manual", help="Source label")
    parser.add_argument("--scope", choices=["global", "stack", "project"],
                        default="global", help="Lesson scope")
    parser.add_argument("--project", "-p", default="", help="Project name (for project scope)")
    parser.add_argument("--tags", default="", help="Comma-separated tech stack tags")
    args = parser.parse_args()

    ensure_dirs()

    existing = [l.get("claim", "") for l in read_jsonl(LESSONS_JSONL)]
    valid, reason = validate(args.claim, existing)
    if not valid:
        print(f"[learn] Rejected: {reason}")
        return 1

    tags = [t.strip() for t in args.tags.split(",") if t.strip()] if args.tags else []

    lesson = {
        "pattern_id": pattern_id(args.claim, []),
        "claim": args.claim,
        "rationale": args.rationale,
        "type": args.type,
        "scope": args.scope,
        "project": args.project if args.scope == "project" else "",
        "tags": tags,
        "source": args.source,
        "graduated_at": now_iso(),
        "graduated_by": "learn",
    }

    append_jsonl(LESSONS_JSONL, lesson)
    count = render_lessons()
    scope_label = f"[{args.scope}]" + (f"/{args.project}" if args.project else "")
    print(f"[learn] Graduated {scope_label}: {args.claim}")
    print(f"[learn] LESSONS.md now has {count} lessons")
    return 0


if __name__ == "__main__":
    sys.exit(main())
