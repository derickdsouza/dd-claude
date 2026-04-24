"""Heuristic candidate validation."""
import re

from .config import MIN_CONTENT_WORDS


def has_min_content_words(text: str, minimum: int = MIN_CONTENT_WORDS) -> bool:
    words = re.findall(r"\b[a-z][a-z0-9_]+\b", text.lower())
    content = [w for w in words if len(w) > 2]
    return len(content) >= minimum


def is_duplicate(claim: str, existing: list[str]) -> bool:
    canonical = " ".join(claim.lower().split())
    return canonical in [" ".join(e.lower().split()) for e in existing]


def validate(claim: str, existing_claims: list[str]) -> tuple[bool, str]:
    if not claim.strip():
        return False, "empty claim"
    if not has_min_content_words(claim):
        return False, f"fewer than {MIN_CONTENT_WORDS} content words"
    if is_duplicate(claim, existing_claims):
        return False, "exact duplicate of existing lesson"
    return True, "valid"
