"""Render lessons.jsonl to LESSONS.md — global + per-project."""
from pathlib import Path

from .config import (
    LESSONS_JSONL, LESSONS_MD, PROJECTS_DIR, MEMORY_DIR,
    SCOPE_GLOBAL, SCOPE_STACK, SCOPE_PROJECT, find_project_dir,
)
from .state import read_jsonl, atomic_write

SENTINEL = "<!-- dream-cycle:auto-generated -->"

HEADER = """\
# Graduated Lessons

Lessons extracted from patterns across memory files.
Managed by `~/.claude/dream-cycle/`. Edit above the sentinel; content below is auto-generated.

"""

SCOPE_LABELS = {
    SCOPE_GLOBAL: "Universal",
    SCOPE_STACK: "Tech Stack",
    SCOPE_PROJECT: "Project-Specific",
}

SCOPE_ORDER = {SCOPE_GLOBAL: 0, SCOPE_STACK: 1, SCOPE_PROJECT: 2}


def _render_section(scope: str, lessons: list[dict], project: str = "") -> list[str]:
    lines = [f"## {SCOPE_LABELS.get(scope, scope)}"
             + (f" — {project}" if project else ""), ""]
    for lesson in lessons:
        claim = lesson.get("claim", "")
        rationale = lesson.get("rationale", "")
        tags = lesson.get("tags", [])
        grad_at = lesson.get("graduated_at", "unknown")[:10]

        entry = f"- **{claim}**"
        if rationale:
            entry += f"\n  - _Why: {rationale}_"
        meta = f"Graduated: {grad_at}"
        if tags:
            meta += f" | Tags: {', '.join(tags)}"
        entry += f"\n  - _{meta}_"
        lines.append(entry)
        lines.append("")
    return lines


def render_lessons() -> int:
    lessons = read_jsonl(LESSONS_JSONL)

    hand_curated = HEADER
    if LESSONS_MD.exists():
        existing = LESSONS_MD.read_text(encoding="utf-8")
        idx = existing.find(SENTINEL)
        if idx >= 0:
            hand_curated = existing[:idx]
        else:
            hand_curated = existing

    lines = [
        SENTINEL,
        f"<!-- {len(lessons)} graduated lessons -->",
        "",
    ]

    # Group by scope then project
    by_scope: dict[str, list[dict]] = {}
    by_project: dict[str, list[dict]] = {}
    for l in lessons:
        scope = l.get("scope", SCOPE_GLOBAL)
        project = l.get("project", "")
        if scope == SCOPE_PROJECT and project:
            by_project.setdefault(project, []).append(l)
        else:
            by_scope.setdefault(scope, []).append(l)

    # Global + Stack sections
    for scope in sorted(by_scope, key=lambda s: SCOPE_ORDER.get(s, 99)):
        lines.extend(_render_section(scope, by_scope[scope]))

    # Project sections
    for project in sorted(by_project):
        lines.extend(_render_section(SCOPE_PROJECT, by_project[project], project))

    output = hand_curated + "\n".join(lines) + "\n"
    atomic_write(LESSONS_MD, output)

    # Also render per-project LESSONS.md into each project's memory dir
    _render_project_files(lessons, by_scope, by_project)

    return len(lessons)


def _render_project_files(
    all_lessons: list[dict],
    by_scope: dict[str, list[dict]],
    by_project: dict[str, list[dict]],
):
    """Write a project-scoped LESSONS.md into each project's memory dir."""
    for project_name, project_lessons in by_project.items():
        raw_dir = find_project_dir(project_name)
        if not raw_dir:
            continue
        project_dir = raw_dir / "memory"
        if not project_dir.exists():
            continue

        project_md = project_dir / "LESSONS.md"
        global_and_stack = by_scope.get(SCOPE_GLOBAL, []) + by_scope.get(SCOPE_STACK, [])

        lines = [
            f"# Graduated Lessons — {project_name}",
            "",
            f"Auto-generated from dream-cycle. Global + stack + this project's lessons.",
            "",
        ]

        if global_and_stack:
            lines.append("## Applicable Global & Stack Lessons")
            lines.append("")
            for l in global_and_stack:
                claim = l.get("claim", "")
                rationale = l.get("rationale", "")
                grad_at = l.get("graduated_at", "unknown")[:10]
                scope = l.get("scope", "")
                entry = f"- **{claim}**"
                if rationale:
                    entry += f"\n  - _Why: {rationale}_"
                entry += f"\n  - _[{scope}] Graduated: {grad_at}_"
                lines.append(entry)
                lines.append("")

        lines.extend(_render_section(SCOPE_PROJECT, project_lessons, project_name))

        atomic_write(project_md, "\n".join(lines) + "\n")
