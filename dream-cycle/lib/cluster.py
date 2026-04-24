"""Single-linkage Jaccard clustering with bridge merging."""
import re
from collections import defaultdict

from .config import STOP_WORDS, JACCARD_THRESHOLD, MIN_CLUSTER_SIZE


def tokenize(text: str) -> set[str]:
    words = re.findall(r"\b[a-z][a-z0-9_]+\b", text.lower())
    return set(words) - STOP_WORDS


def jaccard(a: set[str], b: set[str]) -> float:
    if not a or not b:
        return 0.0
    return len(a & b) / len(a | b)


def cluster_items(
    items: list[dict],
    threshold: float = JACCARD_THRESHOLD,
    min_size: int = MIN_CLUSTER_SIZE,
) -> list[list[dict]]:
    """Single-linkage clustering on items with 'tokens' key."""
    if not items:
        return []

    n = len(items)
    parent = list(range(n))
    rank = [0] * n

    def find(x: int) -> int:
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(a: int, b: int):
        ra, rb = find(a), find(b)
        if ra == rb:
            return
        if rank[ra] < rank[rb]:
            ra, rb = rb, ra
        parent[rb] = ra
        if rank[ra] == rank[rb]:
            rank[ra] += 1

    for i in range(n):
        for j in range(i + 1, n):
            if jaccard(items[i]["tokens"], items[j]["tokens"]) >= threshold:
                union(i, j)

    groups = defaultdict(list)
    for i, item in enumerate(items):
        groups[find(i)].append(item)

    return [g for g in groups.values() if len(g) >= min_size]


def extract_candidate(cluster: list[dict]) -> dict:
    """Pick the most representative item from a cluster as the candidate claim."""
    if len(cluster) == 1:
        return cluster[0]

    scored = []
    for item in cluster:
        overlap = 0
        tokens = item["tokens"]
        for other in cluster:
            if other is item:
                continue
            overlap += len(tokens & other["tokens"])
        scored.append((overlap, item))

    scored.sort(key=lambda x: -x[0])
    return scored[0][1]
