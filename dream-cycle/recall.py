#!/usr/bin/env python3
"""Surface graduated lessons relevant to an intent, with scope awareness.

Usage:
    python3 ~/.claude/dream-cycle/recall.py "add a created_at column"
    python3 ~/.claude/dream-cycle/recall.py "deploy to production" --scope global
    python3 ~/.claude/dream-cycle/recall.py "tradex order" --project portfolio-manager
    python3 ~/.claude/dream-cycle/recall.py "redis cache" --tags redis,bullmq
"""
import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from lib.config import (
    ensure_dirs, LESSONS_JSONL, EPISODES_JSONL,
    SCOPE_GLOBAL, SCOPE_STACK, SCOPE_PROJECT,
    resolve_project_from_cwd,
)
from lib.state import read_jsonl, append_jsonl, now_iso
from lib.cluster import tokenize, jaccard


def main():
    parser = argparse.ArgumentParser(description="Recall relevant lessons")
    parser.add_argument("query", help="What you're about to do")
    parser.add_argument("--top", "-n", type=int, default=5, help="Max results")
    parser.add_argument("--scope", "-s", choices=["global", "stack", "project", "all"],
                        default="all", help="Filter by scope")
    parser.add_argument("--project", "-p", default="", help="Filter to project name")
    parser.add_argument("--tags", "-t", default="", help="Comma-separated tags to match")
    args = parser.parse_args()

    ensure_dirs()

    lessons = read_jsonl(LESSONS_JSONL)
    if not lessons:
        print("[recall] No graduated lessons yet. Use learn.py or graduate a candidate.")
        return 0

    # Auto-detect project from CWD if not specified
    project = args.project
    if not project and args.scope == "all":
        project, _ = resolve_project_from_cwd()

    filter_tags = set(t.strip() for t in args.tags.split(",") if t.strip()) if args.tags else set()

    # Filter lessons by scope
    filtered = []
    for l in lessons:
        l_scope = l.get("scope", SCOPE_GLOBAL)
        l_project = l.get("project", "")

        if args.scope != "all":
            if args.scope == "project" and l_scope != SCOPE_PROJECT:
                continue
            if args.scope == "global" and l_scope not in (SCOPE_GLOBAL, SCOPE_STACK):
                continue
            if args.scope == "stack" and l_scope != SCOPE_STACK:
                continue

        # If project context known, include global + stack + that project's lessons
        if project and args.scope == "all":
            if l_scope == SCOPE_PROJECT and l_project and l_project != project:
                continue

        # Filter by tags
        if filter_tags:
            l_tags = set(l.get("tags", []))
            if not filter_tags & l_tags:
                continue

        filtered.append(l)

    if not filtered:
        print(f"[recall] No lessons match filters (scope={args.scope}, project={project or 'any'}, tags={filter_tags or 'any'})")
        return 0

    query_tokens = tokenize(args.query)
    if not query_tokens:
        print("[recall] Query too short to match.")
        return 0

    scored = []
    for lesson in filtered:
        claim = lesson.get("claim", "")
        rationale = lesson.get("rationale", "")
        tags_text = " ".join(lesson.get("tags", []))
        lesson_tokens = tokenize(f"{claim} {rationale} {tags_text}")
        score = jaccard(query_tokens, lesson_tokens)
        if score > 0:
            scored.append((score, lesson))

    scored.sort(key=lambda x: -x[0])
    results = scored[:args.top]

    if not results:
        print(f"[recall] No lessons match '{args.query}' within scope filter")
        return 0

    print(f"[recall] Top {len(results)} for '{args.query}'"
          f" (scope={args.scope}, project={project or 'any'}):\n")
    for i, (score, lesson) in enumerate(results, 1):
        claim = lesson["claim"]
        rationale = lesson.get("rationale", "")
        source = lesson.get("source", "unknown")
        l_scope = lesson.get("scope", SCOPE_GLOBAL)
        l_project = lesson.get("project", "")
        tags = lesson.get("tags", [])
        grad_at = lesson.get("graduated_at", "unknown")[:10]

        scope_label = l_scope
        if l_project:
            scope_label += f"/{l_project}"

        print(f"  {i}. [{score:.2f}] [{scope_label}] {claim}")
        if rationale:
            print(f"     Why: {rationale}")
        tag_str = f" | Tags: {', '.join(tags)}" if tags else ""
        print(f"     Source: {source} | Graduated: {grad_at}{tag_str}")
        print()

    append_jsonl(EPISODES_JSONL, {
        "action": "recall",
        "query": args.query,
        "scope": args.scope,
        "project": project,
        "results": len(results),
        "top_score": results[0][0] if results else 0,
        "timestamp": now_iso(),
    })

    return 0


if __name__ == "__main__":
    sys.exit(main())
