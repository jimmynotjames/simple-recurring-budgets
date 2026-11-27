"""This app's localization data, read from the repo's i18n/ folder.

The pipeline code under scripts/translate_* is identical in every app that uses it; everything
app-specific lives in i18n/ and is read here, so no script restates a brand, a path, a note or an
allowlist. Import; never restate.

  i18n/app.json                     brand, protected terms, paths, metadata fields, spec pointer
  i18n/brief.md                     the app's prose fragments for the prompt templates
  i18n/regional_notes.json          in-app register, dialect and script notes per runtime locale
  i18n/cultural_notes.json          store-listing market notes per storefront
  i18n/glossary.json                agreed per-locale renderings of recurring terms
  i18n/glossary_ignore.json         repeated English strings that are not terminology
  i18n/untranslated_allowlist.json  (key, locale) pairs deliberately identical to English
  i18n/distinct_pairs.json          key pairs that must not render identically
"""

from __future__ import annotations

import json
import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
I18N_DIR = REPO_ROOT / "i18n"
GLOSSARY_PATH = I18N_DIR / "glossary.json"


def _json(name: str):
    path = I18N_DIR / name
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except OSError as exc:
        raise RuntimeError(f"localization data unreadable at {path}: {exc}") from exc


APP: dict = _json("app.json")

BRAND: str = APP["brand"]
PROTECTED: list[str] = list(APP["protected"])
TRANSCREATED_NAMESPACES: tuple[str, ...] = tuple(APP.get("transcreatedNamespaces", ()))
SPEC: str = APP["spec"]

_regional = _json("regional_notes.json")
REGIONAL_NOTES: dict[str, str] = _regional["locales"]
GENERIC_REGIONAL_NOTE: str = _regional["generic"]

_cultural = _json("cultural_notes.json")
CULTURAL_NOTES: dict[str, str] = _cultural["storefronts"]
GENERIC_CULTURAL_NOTE: str = _cultural["generic"]


def repo_path(key: str) -> Path:
    """An `app.json` `paths` entry as an absolute path."""
    return REPO_ROOT / APP["paths"][key]


_FRAGMENT_RE = re.compile(r"^<!-- fragment ([A-Z][A-Z_]*) -->\n(.*?)\n<!-- end \1 -->$", re.S | re.M)


def _load_brief() -> dict[str, str]:
    text = (I18N_DIR / "brief.md").read_text(encoding="utf-8")
    fragments = dict(_FRAGMENT_RE.findall(text))
    reserved = {"APP_NAME", "PROTECTED_QUOTED"} & fragments.keys()
    if reserved:
        raise RuntimeError(f"i18n/brief.md: fragment names reserved for app.json values: {sorted(reserved)}")
    return fragments


BRIEF: dict[str, str] = _load_brief()


def _quoted(terms: list[str]) -> str:
    quoted = [f'"{term}"' for term in terms]
    return quoted[0] if len(quoted) == 1 else ", ".join(quoted[:-1]) + " and " + quoted[-1]


# App values every template may use, alongside the brief fragments.
APP_VALUES: dict[str, str] = {"APP_NAME": BRAND, "PROTECTED_QUOTED": _quoted(PROTECTED)}

_PLACEHOLDER_RE = re.compile(r"\{([A-Z][A-Z_]*)\}")


def load_template(path: Path) -> str:
    """A prompt template with this app's brief fragments and app values filled in.

    Two passes: fragments first, then app values, so a fragment may say {APP_NAME}. Fragments
    may also carry the template's own placeholders ({LOCALE_NAME}); those are left for
    prompt_render.render, which raises on any placeholder still unfilled after that.
    """
    text = path.read_text(encoding="utf-8")
    for values in (BRIEF, APP_VALUES):
        text = _PLACEHOLDER_RE.sub(lambda m: values.get(m.group(1), m.group(0)), text)
    return text


def glossary_ignore() -> set[str]:
    """English strings glossary_sync.py never proposes as terms; each row carries its reason."""
    return {row["en"] for row in _json("glossary_ignore.json")}


def untranslated_allowlist() -> set[tuple[str, str]]:
    return {(row["key"], row["locale"]) for row in _json("untranslated_allowlist.json")}


def distinct_pairs() -> list[tuple[str, str, str]]:
    return [(row["keys"][0], row["keys"][1], row["reason"]) for row in _json("distinct_pairs.json")]
