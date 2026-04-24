#!/usr/bin/env python3
"""Graduate a candidate lesson with required rationale.

Usage:
    python3 ~/.claude/dream-cycle/graduate.py abc12345 --rationale "evidence holds across multiple projects"
"""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from lib.config import ensure_dirs, CANDIDATES_JSONL, LESSONS_JSONL, DECISIONS_JSONL
from lib.state import read_jsonl, rewrite_jsonl, append_jsonl, now_iso
from lib.render import render_lessons


def main():
    parser = argparse.ArgumentParser(description="Graduate a candidate lesson")
    parser.add_argument("pattern_id", help="Pattern ID (or first 8+ chars)")
    parser.add_argument("--rationale", "-r", required=True, help="Why this lesson is accepted (required)")
    args = parser.parse_args()

    ensure_dirs()

    candidates = read_jsonl(CANDIDATES_JSONL)
    match = None
    for c in candidates:
        if c.get("pattern_id", "").startswith(args.pattern_id):
            match = c
            break

    if not match:
        print(f"[graduate] No candidate matching '{args.pattern_id}'")
        return 1

    if match.get("status") != "staged":
        print(f"[graduate] Candidate is {match.get('status')}, not staged")
        return 1

    lesson = {
        "pattern_id": match["pattern_id"],
        "claim": match["claim"],
        "conditions": match.get("conditions", []),
        "type": ", ".join(match.get("member_types", [])),
        "scope": match.get("scope", "global"),
        "project": match.get("project", ""),
        "tags": match.get("tags", []),
        "source": "auto_dream",
        "member_ids": match.get("member_ids", []),
        "rationale": args.rationale,
        "graduated_at": now_iso(),
        "graduated_by": "host_agent",
    }

    append_jsonl(LESSONS_JSONL, lesson)

    match["status"] = "graduated"
    match["graduated_at"] = now_iso()
    rewrite_jsonl(CANDIDATES_JSONL, candidates)

    append_jsonl(DECISIONS_JSONL, {
        "pattern_id": match["pattern_id"],
        "action": "graduate",
        "rationale": args.rationale,
        "scope": lesson["scope"],
        "project": lesson["project"],
        "timestamp": now_iso(),
    })

    count = render_lessons()
    scope_label = f"[{lesson['scope']}]"
    if lesson.get("project"):
        scope_label += f"/{lesson['project']}"
    print(f"[graduate] Graduated {scope_label}: {match['claim']}")
    print(f"[graduate] LESSONS.md now has {count} lessons")
    return 0


if __name__ == "__main__":
    sys.exit(main())
