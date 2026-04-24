#!/usr/bin/env python3
"""List pending candidates sorted by cluster size (priority).

Usage:
    python3 ~/.claude/dream-cycle/list_candidates.py
    python3 ~/.claude/dream-cycle/list_candidates.py --scope stack
    python3 ~/.claude/dream-cycle/list_candidates.py --all
    python3 ~/.claude/dream-cycle/list_candidates.py --json
"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from lib.config import ensure_dirs, CANDIDATES_JSONL
from lib.state import read_jsonl


def main():
    parser = argparse.ArgumentParser(description="List dream-cycle candidates")
    parser.add_argument("--all", action="store_true", help="Include rejected/closed")
    parser.add_argument("--scope", "-s", default="", choices=["global", "stack", "project", ""],
                        help="Filter by scope")
    parser.add_argument("--json", action="store_true", help="JSON output")
    args = parser.parse_args()

    ensure_dirs()
    candidates = read_jsonl(CANDIDATES_JSONL)

    if not args.all:
        candidates = [c for c in candidates if c.get("status") == "staged"]

    if args.scope:
        candidates = [c for c in candidates if c.get("scope") == args.scope]

    candidates.sort(key=lambda c: -c.get("cluster_size", 0))

    if args.json:
        print(json.dumps(candidates, indent=2))
        return 0

    if not candidates:
        print("[candidates] No matching candidates.")
        return 0

    print(f"[candidates] {len(candidates)} matching:\n")
    for i, c in enumerate(candidates, 1):
        pid = c.get("pattern_id", "?")[:8]
        claim = c.get("claim", "?")
        scope = c.get("scope", "?")
        project = c.get("project", "")
        members = c.get("member_ids", [])
        types = c.get("member_types", [])
        size = c.get("cluster_size", 0)
        tags = c.get("tags", [])
        staged = c.get("staged_at", "?")[:10]
        status = c.get("status", "staged")

        scope_label = scope + (f"/{project}" if project else "")
        tag_str = f" | Tags: {', '.join(tags[:4])}" if tags else ""

        print(f"  {i}. [{pid}] [{scope_label}] {claim}")
        print(f"     Status: {status} | Cluster: {size} | Types: {', '.join(types)}{tag_str}")
        print(f"     Members: {', '.join(members[:5])}{' +' + str(len(members) - 5) + ' more' if len(members) > 5 else ''}")
        print(f"     Staged: {staged}")
        print()

    return 0


if __name__ == "__main__":
    sys.exit(main())
