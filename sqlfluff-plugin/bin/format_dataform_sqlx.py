#!/usr/bin/env python3
r"""Format a Dataform .sqlx file with SQLFluff.

.sqlx files aren't plain SQL: they start with a JS/JSON-like ``config {
... }`` block and can embed ``${...}`` interpolations (``${ref("...")}``,
``${when(incremental(), `...${self()}...`)}``, etc), which can nest
arbitrarily. SQLFluff's parser chokes on all of that, so it refuses to
format the file at all. This script:

1. Strips the leading ``config { ... }`` block off (kept verbatim).
2. Replaces every top-level ``${...}`` interpolation (nesting-aware) with
   a placeholder so the remaining text parses as valid SQL:
   - interpolations that sit alone on their own line (e.g. a conditional
     ``${when(...)}`` appended to a WHERE clause) become a line comment,
     since a comment is valid in any clause position;
   - interpolations embedded inline (e.g. ``FROM ${ref("...")}``) become
     a bare placeholder identifier, since they always sit in a table- or
     column-reference position.
3. Runs SQLFluff's fixer on just that SQL body.
4. Restores the original interpolations and re-attaches the config block.

Plain .sql files (no config block, no interpolations) pass through
unchanged other than the SQLFluff formatting itself.
"""

import os
import re
import subprocess
import sys

SQLFLUFF = os.path.expanduser("~/.local/share/sqlfluff-venv/bin/sqlfluff")

CONFIG_BLOCK_RE = re.compile(r"\A(config\s*\{.*?\n\}\s*\n?)", re.DOTALL)
PLACEHOLDER_RE = re.compile(
    r"(?P<indent>[ \t]*)--[ \t]*__dataform_placeholder_(?P<comment_idx>\d+)__"
    r"|(?:AND|OR)[ \t]+__dataform_placeholder_(?P<cond_idx>\d+)__"
    r"|__dataform_placeholder_(?P<inline_idx>\d+)__"
)


def find_interpolations(text: str) -> list[tuple[int, int]]:
    """Find top-level (nesting-aware) `${...}` spans as (start, end) pairs."""
    spans = []
    i = 0
    n = len(text)
    while i < n:
        if text[i] == "$" and i + 1 < n and text[i + 1] == "{":
            depth = 0
            j = i + 1
            while j < n:
                if text[j] == "{":
                    depth += 1
                elif text[j] == "}":
                    depth -= 1
                    if depth == 0:
                        j += 1
                        break
                j += 1
            spans.append((i, j))
            i = j
        else:
            i += 1
    return spans


def stash_interpolations(body: str) -> tuple[str, list[str]]:
    placeholders: list[str] = []
    out = []
    cursor = 0
    for start, end in find_interpolations(body):
        line_start = body.rfind("\n", 0, start) + 1
        line_end = body.find("\n", end)
        if line_end == -1:
            line_end = len(body)
        standalone = body[line_start:start].strip() == "" and body[end:line_end].strip() == ""

        token = body[start:end]
        idx = len(placeholders)
        placeholders.append(token)

        # Dataform's `${when(incremental(), `AND ...`)}` convention embeds a
        # conditional AND/OR fragment. Treat those as a real AND/OR condition
        # (rather than an opaque comment) so SQLFluff's normal WHERE-clause
        # layout rules place and indent it exactly like any other condition.
        conditional = re.search(r"`\s*(AND|OR)\b", token, re.IGNORECASE)

        if standalone and conditional:
            keyword = conditional.group(1).upper()
            out.append(body[cursor:start])
            out.append(f"{keyword} __dataform_placeholder_{idx}__")
            cursor = end
        elif standalone:
            out.append(body[cursor:start])
            out.append(f"-- __dataform_placeholder_{idx}__")
            cursor = line_end
        else:
            out.append(body[cursor:start])
            out.append(f"__dataform_placeholder_{idx}__")
            cursor = end
    out.append(body[cursor:])
    return "".join(out), placeholders


def restore_interpolations(text: str, placeholders: list[str]) -> str:
    def sub(match: "re.Match[str]") -> str:
        if match.group("comment_idx") is not None:
            return match.group("indent") + placeholders[int(match.group("comment_idx"))]
        if match.group("cond_idx") is not None:
            return placeholders[int(match.group("cond_idx"))]
        return placeholders[int(match.group("inline_idx"))]

    return PLACEHOLDER_RE.sub(sub, text)


def main() -> None:
    src = sys.stdin.read()

    config_match = CONFIG_BLOCK_RE.match(src)
    prefix = config_match.group(1) if config_match else ""
    body = src[config_match.end() :] if config_match else src

    stashed_body, placeholders = stash_interpolations(body)

    proc = subprocess.run(
        [SQLFLUFF, "fix", "--disable-progress-bar", "-n", "-"],
        input=stashed_body,
        capture_output=True,
        text=True,
    )
    formatted = proc.stdout if proc.stdout.strip() else stashed_body
    formatted = restore_interpolations(formatted, placeholders)

    sys.stdout.write(prefix + formatted)


if __name__ == "__main__":
    main()
