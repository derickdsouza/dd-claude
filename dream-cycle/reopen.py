#!/usr/bin/env python3
"""Reopen a previously rejected candidate for re-review.

Usage:
    python3 ~/.claude/dream-cycle/reopen.py abc12345
"""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from lib.config import ensure_dirs, CANDIDATES_JSONL, DECISIONS_JSONL
from lib.state import read_jsonl, rewrite_jsonl, append_jsonl, now_iso


def main():
    parser = argparse.ArgumentParser(description="Reopen a rejected candidate")
    parser.add_argument("pattern_id", help="Pattern ID (or first 8+ chars)")
    args = parser.parse_args()

    ensure_dirs()

    candidates = read_jsonl(CANDIDATES_JSONL)
    match = None
    for c in candidates:
        if c.get("pattern_id", "").startswith(args.pattern_id):
            match = c
            break

    if not match:
        print(f"[reopen] No candidate matching '{args.pattern_id}'")
        return 1

    if match.get("status") != "rejected":
        print(f"[reopen] Candidate is '{match.get('status')}', not rejected")
        return 1

    match["status"] = "staged"
    match["reopened_at"] = now_iso()
    rewrite_jsonl(CANDIDATES_JSONL, candidates)

    append_jsonl(DECISIONS_JSONL, {
        "pattern_id": match["pattern_id"],
        "action": "reopen",
        "timestamp": now_iso(),
    })

    print(f"[reopen] Reopened: {match.get('claim', '?')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
