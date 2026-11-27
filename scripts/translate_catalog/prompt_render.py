"""Fill a pipeline prompt template: optional sections, placeholders, and compact JSON slices.

A template marks an optional section as `<!-- if NAME -->` … `<!-- end NAME -->` on their own
lines; `render` keeps it only when NAME is enabled, and raises on a section name outside
`known`, so a renamed section can't silently drop a rule block. Sections may nest. Placeholders are `{UPPER_SNAKE}`,
filled in one pass so text inside a substituted value is never re-scanned; a placeholder with no
value raises, so no `{…}` can reach a subagent.
"""

from __future__ import annotations

import json
import re

_SECTION_RE = re.compile(r"^<!-- if (\w+) -->\n(.*?)^<!-- end \1 -->\n", re.S | re.M)
_PLACEHOLDER_RE = re.compile(r"\{([A-Z][A-Z_]*)\}")


def render(
    template: str,
    values: dict[str, str],
    sections: set[str] | frozenset[str] = frozenset(),
    known: set[str] | frozenset[str] = frozenset(),
) -> str:
    text = template
    while True:  # one pass per nesting level: a kept section may hold another
        found = _SECTION_RE.findall(text)
        if not found:
            break
        unknown = sorted({name for name, _ in found} - set(known))
        if unknown:
            raise KeyError(f"template sections the renderer doesn't know: {unknown}")
        text = _SECTION_RE.sub(lambda m: m.group(2) if m.group(1) in sections else "", text)
    missing = sorted({name for name in _PLACEHOLDER_RE.findall(text) if name not in values})
    if missing:
        raise KeyError(f"template placeholders with no value: {missing}")
    text = _PLACEHOLDER_RE.sub(lambda m: values[m.group(1)], text)
    return re.sub(r"\n{3,}", "\n\n", text)


def compact_json(obj: dict) -> str:
    """One top-level entry per line with no inner whitespace."""
    lines = [
        f"{json.dumps(key, ensure_ascii=False)}:{json.dumps(obj[key], ensure_ascii=False, sort_keys=True, separators=(',', ':'))}"
        for key in sorted(obj)
    ]
    return "{\n" + ",\n".join(lines) + "\n}"
