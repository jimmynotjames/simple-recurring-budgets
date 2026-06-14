"""Shared utility for writing Localizable.xcstrings in Xcode's canonical format."""
from __future__ import annotations

import json
from pathlib import Path


def write_xcstrings(catalog: dict, path: Path) -> None:
    out = json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True)
    # Xcode serializes xcstrings with a space before colons ("key" : "value").
    # json.dumps escapes all in-string quotes as \", so literal '": ' only
    # appears at key-value boundaries — safe to replace globally.
    out = out.replace('": ', '" : ')
    path.write_text(out + "\n", encoding="utf-8")
