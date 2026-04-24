#!/usr/bin/env python3
"""Nightly dream cycle — scan memory, cluster patterns, stage candidates.

This is the mechanical half. No reasoning, no git commits, no network.
Safe to run unattended via cron.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from lib.config import ensure_dirs, CANDIDATES_JSONL, LESSONS_JSONL
from lib.state import read_jsonl, append_jsonl, now_iso, pattern_id
from lib.scanner import scan_memory
from lib.cluster import cluster_items, extract_candidate
from lib.validate import validate


def main():
    ensure_dirs()

    items = scan_memory()
    if not items:
        print("[dream] No memory items found. Nothing to dream about.")
        return 0

    by_scope = {}
    for it in items:
        by_scope.setdefault(it["scope"], []).append(it)
    print(f"[dream] Scanned {len(items)} memory items ({', '.join(f'{k}: {len(v)}' for k, v in sorted(by_scope.items()))})")

    clusters = cluster_items(items)
    print(f"[dream] Found {len(clusters)} clusters (threshold=0.30)")

    if not clusters:
        print("[dream] No significant pattern clusters. Exiting.")
        return 0

    existing_claims = [l.get("claim", "") for l in read_jsonl(LESSONS_JSONL)]
    candidates = read_jsonl(CANDIDATES_JSONL)
    candidate_claims = [c.get("claim", "") for c in candidates]
    all_existing = existing_claims + candidate_claims

    staged = 0
    skipped = 0

    for cluster in clusters:
        rep = extract_candidate(cluster)
        claim = rep.get("description") or rep.get("name", "")
        if not claim:
            continue

        conditions = [it["name"] for it in cluster]
        pid = pattern_id(claim, conditions)

        if any(c.get("pattern_id") == pid for c in candidates):
            skipped += 1
            continue

        valid, reason = validate(claim, all_existing)
        if not valid:
            skipped += 1
            continue

        member_ids = [it["id"] for it in cluster]
        member_types = list(set(it.get("type", "unknown") for it in cluster))
        member_scopes = list(set(it.get("scope", "global") for it in cluster))
        member_projects = list(set(it.get("project", "") for it in cluster))
        member_projects = [p for p in member_projects if p]

        # Determine candidate scope: if all members share a project → project,
        # if mixed or global/stack → use the most specific common scope
        if len(member_projects) == 1:
            cand_scope = "project"
            cand_project = member_projects[0]
        elif member_scopes == ["global"]:
            cand_scope = "global"
            cand_project = ""
        else:
            cand_scope = "stack"
            cand_project = ""

        all_tags = set()
        for it in cluster:
            all_tags.update(it.get("tags", []))

        candidate = {
            "pattern_id": pid,
            "claim": claim,
            "conditions": conditions,
            "member_ids": member_ids,
            "member_types": member_types,
            "cluster_size": len(cluster),
            "scope": cand_scope,
            "project": cand_project,
            "tags": sorted(all_tags),
            "source": "auto_dream",
            "staged_at": now_iso(),
            "status": "staged",
        }

        append_jsonl(CANDIDATES_JSONL, candidate)
        all_existing.append(claim)
        staged += 1

        sources = ", ".join(member_ids[:4])
        if len(member_ids) > 4:
            sources += f" +{len(member_ids) - 4} more"
        print(f"  [+] staged [{cand_scope}]: {claim[:60]}... ({sources})")

    print(f"[dream] Staged {staged} new candidates, skipped {skipped}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
