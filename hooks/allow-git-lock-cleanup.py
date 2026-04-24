#!/usr/bin/env python3

import json
import re
import sys
from pathlib import Path


LOCK_BASENAMES = {"index.lock", "background-refresh.lock"}
SAFE_PIPE_COMMANDS = ("tail ", "head ", "grep ", "sed ", "cat ")


def load_payload():
    try:
        return json.load(sys.stdin)
    except json.JSONDecodeError:
        return None


def is_git_lock_path(path_str: str) -> bool:
    if not path_str:
        return False

    path = Path(path_str).expanduser()
    name = path.name
    if not (name.endswith(".lock") or ".lock" in name):
        return False

    parts = path.parts
    return ".git" in parts


def matches_safe_rm(rule_or_command: str) -> bool:
    text = rule_or_command.strip()
    if not text.startswith("rm -f "):
        return False

    if "&&" in text or "||" in text or "\n" in text:
        return False

    if ";" in text:
        rm_part, remainder = text.split(";", 1)
        text = rm_part.strip()
        remainder = remainder.strip()
        if not remainder.startswith("but "):
            return False
        if "&&" in remainder or "||" in remainder or ";" in remainder or "\n" in remainder:
            return False
        if "|&" in remainder:
            _, pipe_cmd = remainder.split("|&", 1)
            if not pipe_cmd.strip().startswith(SAFE_PIPE_COMMANDS):
                return False
        elif "|" in remainder:
            _, pipe_cmd = remainder.split("|", 1)
            if not pipe_cmd.strip().startswith(SAFE_PIPE_COMMANDS):
                return False

    if text.endswith(" 2>/dev/null"):
        text = text[: -len(" 2>/dev/null")].rstrip()

    targets = text[len("rm -f ") :].split()
    if not targets:
        return False

    for target in targets:
        if "*" in target:
            if not re.search(r"/?\.git/\*\.lock\*?$", target):
                return False
            continue

        path = Path(target).expanduser()
        if path.name not in LOCK_BASENAMES and not path.name.endswith(".lock"):
            return False
        if ".git" not in path.parts:
            return False

    return True


def should_allow(payload: dict) -> bool:
    tool_name = payload.get("tool_name")

    if tool_name in {"Edit", "Write"}:
        file_path = payload.get("tool_input", {}).get("file_path", "")
        return is_git_lock_path(file_path)

    if tool_name != "Bash":
        return False

    suggestions = payload.get("permission_suggestions") or []
    for suggestion in suggestions:
        for rule in suggestion.get("rules", []):
            rule_content = rule.get("ruleContent", "")
            if matches_safe_rm(rule_content):
                return True

    command = payload.get("tool_input", {}).get("command", "")
    return matches_safe_rm(command)


def main():
    payload = load_payload()
    if not payload or not should_allow(payload):
        return 0

    json.dump(
        {
            "hookSpecificOutput": {
                "hookEventName": "PermissionRequest",
                "decision": {"behavior": "allow"},
            }
        },
        sys.stdout,
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
