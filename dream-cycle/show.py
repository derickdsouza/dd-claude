#!/usr/bin/env python3
"""Dashboard of dream-cycle brain state with scope breakdown.

Usage:
    python3 ~/.claude/dream-cycle/show.py
    python3 ~/.claude/dream-cycle/show.py --json
    python3 ~/.claude/dream-cycle/show.py --plain
"""
import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from lib.config import (
    ensure_dirs, DATA_DIR, LESSONS_JSONL, CANDIDATES_JSONL,
    DECISIONS_JSONL, EPISODES_JSONL,
)
from lib.state import read_jsonl


def sparkline(counts: list[int], chars: str = "_▁▂▃▄▅▆▇█") -> str:
    if not counts or max(counts) == 0:
        return chars[0] * len(counts)
    mx = max(counts)
    step = mx / (len(chars) - 1)
    return "".join(chars[min(int(c / step), len(chars) - 1)] if c else chars[0] for c in counts)


def activity_14d(episodes: list[dict]) -> list[int]:
    now = datetime.now(timezone.utc)
    buckets = [0] * 14
    for ep in episodes:
        ts = ep.get("timestamp", "")
        if not ts:
            continue
        try:
            dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
            days_ago = (now - dt).days
            if 0 <= days_ago < 14:
                buckets[13 - days_ago] += 1
        except (ValueError, TypeError):
            continue
    return buckets


def main():
    parser = argparse.ArgumentParser(description="Dream-cycle dashboard")
    parser.add_argument("--json", action="store_true", help="JSON output")
    parser.add_argument("--plain", action="store_true", help="No ANSI colors")
    args = parser.parse_args()

    ensure_dirs()

    lessons = read_jsonl(LESSONS_JSONL)
    candidates = read_jsonl(CANDIDATES_JSONL)
    decisions = read_jsonl(DECISIONS_JSONL)
    episodes = read_jsonl(EPISODES_JSONL)

    staged = [c for c in candidates if c.get("status") == "staged"]
    rejected = [d for d in decisions if d.get("action") == "reject"]

    # Scope breakdown
    lessons_by_scope = {"global": 0, "stack": 0, "project": {}}
    for l in lessons:
        scope = l.get("scope", "global")
        project = l.get("project", "")
        if scope == "project" and project:
            lessons_by_scope["project"][project] = lessons_by_scope["project"].get(project, 0) + 1
        else:
            lessons_by_scope[scope] = lessons_by_scope.get(scope, 0) + 1

    stats = {
        "lessons": len(lessons),
        "lessons_global": lessons_by_scope["global"],
        "lessons_stack": lessons_by_scope["stack"],
        "lessons_project": lessons_by_scope["project"],
        "candidates_staged": len(staged),
        "candidates_total": len(candidates),
        "decisions": len(decisions),
        "episodes": len(episodes),
        "rejected": len(rejected),
        "activity_14d": activity_14d(episodes),
    }

    if args.json:
        print(json.dumps(stats, indent=2))
        return 0

    B = "\033[1m" if not args.plain else ""
    R = "\033[0m" if not args.plain else ""
    G = "\033[32m" if not args.plain else ""
    Y = "\033[33m" if not args.plain else ""
    C = "\033[36m" if not args.plain else ""
    DIM = "\033[2m" if not args.plain else ""
    M = "\033[35m" if not args.plain else ""

    spark = sparkline(stats["activity_14d"])

    print(f"\n{B}Dream Cycle — Brain State{R}")
    print(f"{'─' * 40}")
    print(f"  {G}Graduated lessons{R}:  {stats['lessons']}")
    print(f"    {DIM}Global:  {stats['lessons_global']}{R}")
    print(f"    {DIM}Stack:   {stats['lessons_stack']}{R}")
    for proj, count in stats["lessons_project"].items():
        print(f"    {M}Project [{proj}]: {count}{R}")
    print(f"  {Y}Pending candidates{R}:  {stats['candidates_staged']}")
    print(f"  Total candidates:  {stats['candidates_total']}")
    print(f"  Decisions made:    {stats['decisions']}")
    print(f"  Episodes logged:   {stats['episodes']}")
    print(f"  Rejected:          {stats['rejected']}")
    print(f"\n  {C}14-day activity{R}: {DIM}{spark}{R}")
    print(f"  {'─' * 14}")
    print()

    if staged:
        print(f"  {Y}Pending review:{R}")
        for c in staged[:10]:
            claim = c.get("claim", "?")[:55]
            scope = c.get("scope", "?")
            members = len(c.get("member_ids", []))
            tags = c.get("tags", [])
            tag_str = f" [{', '.join(tags[:3])}]" if tags else ""
            print(f"    [{c.get('pattern_id', '?')[:8]}] [{scope}]{tag_str} {claim}... ({members} members)")
        if len(staged) > 10:
            print(f"    ... and {len(staged) - 10} more")

    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
