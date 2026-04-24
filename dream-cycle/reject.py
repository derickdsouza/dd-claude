#!/usr/bin/env python3
"""Reject a candidate lesson with required reason.

Usage:
    python3 ~/.claude/dream-cycle/reject.py abc12345 --reason "too specific to generalize"
"""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from lib.config import ensure_dirs, CANDIDATES_JSONL, DECISIONS_JSONL
from lib.state import read_jsonl, rewrite_jsonl, append_jsonl, now_iso


def main():
    parser = argparse.ArgumentParser(description="Reject a candidate lesson")
    parser.add_argument("pattern_id", help="Pattern ID (or first 8+ chars)")
    parser.add_argument("--reason", "-r", required=True, help="Why rejected (required)")
    args = parser.parse_args()

    ensure_dirs()

    candidates = read_jsonl(CANDIDATES_JSONL)
    match = None
    for c in candidates:
        if c.get("pattern_id", "").startswith(args.pattern_id):
            match = c
            break

    if not match:
        print(f"[reject] No candidate matching '{args.pattern_id}'")
        return 1

    match["status"] = "rejected"
    match["rejected_at"] = now_iso()
    rewrite_jsonl(CANDIDATES_JSONL, candidates)

    append_jsonl(DECISIONS_JSONL, {
        "pattern_id": match["pattern_id"],
        "action": "reject",
        "reason": args.reason,
        "timestamp": now_iso(),
    })

    print(f"[reject] Rejected: {match.get('claim', '?')}")
    print(f"[reject] Reason: {args.reason}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
