"""
Single source of truth for per-locale register / formality guidance.

The register core is shared by:
  - scripts/translate_catalog/dispatch_prompts.py  (UI copy → REGIONAL_NOTES)
  - scripts/translate_metadata/dispatch_prompts.py   (ASO copy → CULTURAL_NOTES)
  - scripts/translate_audit/audit_dispatch.py        (via REGIONAL_NOTES import)

Each pipeline composes its full per-locale note from REGISTER[locale] plus a
domain-specific addendum (UI dialect/length notes; ASO positioning/keyword notes).
Neither pipeline restates the formality rule independently.

Import REGISTER, GENERIC_REGISTER, and compose_note from this module.
"""

from __future__ import annotations

# Fallback register rule when a locale has no explicit REGISTER entry (should not
# happen once LOCALES is fully covered — see check_locale_register.py).
GENERIC_REGISTER = (
    "Use the informal address if modern youth-oriented app copy in this language "
    "uses it, but keep the polite/formal form if this language stays formal in app "
    "copy regardless of audience age — get the modern feel from fresh, light "
    "phrasing, not forced slang."
)

# Per-runtime-locale register / formality core. Keys match locales.py LOCALES.
REGISTER: dict[str, str] = {
    "ar": (
        "Modern Standard Arabic (MSA), not a regional dialect — MSA addresses all "
        "audiences with the same standard forms, so there is no casual/formal toggle; "
        "get a warm, contemporary feel through fresh, light phrasing."
    ),
    "ca": "Natural, friendly Catalan as used in Apple's Catalan UI.",
    "cs": "Czech app tone; natural phrasing over literal calques.",
    "da": "Informal, direct Danish — the norm for consumer apps.",
    "de": (
        'Use the informal "du" — standard for German consumer/finance apps aimed at '
        "younger users (N26, Trade Republic). Warm and direct; avoid stiff "
        "officialese and English calques."
    ),
    "el": "Greek; avoid overly formal or bureaucratic phrasing.",
    "en-AU": (
        'Australian English spelling and idiom (e.g. "organise", "colour"). '
        "Relaxed, friendly tone."
    ),
    "en-CA": 'Canadian English spelling (mostly British: "colour", "centre").',
    "en-GB": (
        'British English spelling and idiom (e.g. "organise", "colour", "centre").'
    ),
    "es": (
        'Castilian Spanish; informal "tú" (standard for youth-oriented consumer apps), '
        'not a "vosotros"-formal register. Spain vocabulary (e.g. "móvil"). Modern, relaxed.'
    ),
    "es-MX": (
        'Latin American Spanish; informal "tú". Neutral LatAm vocabulary (e.g. '
        '"celular"); avoid Spain-specific terms.'
    ),
    "fi": "Finnish app tone, not literal.",
    "fr": (
        'Use the informal "tu" — younger French fintech/lifestyle apps (Lydia, Revolut FR) '
        "address under-35s with \"tu\". Elegant and concise; prefer natural French terms "
        "over anglicisms. French app copy prizes clarté and a refined, slightly "
        "understated register over an enthusiastic one."
    ),
    "fr-CA": (
        'Canadian French; informal "tu" (standard in Québécois consumer-app copy). Prefer '
        "Québécois usage and OQLF-style avoidance of anglicisms where they differ from "
        "France French."
    ),
    "he": "Modern Hebrew.",
    "hi": (
        'Conversational Hindi in Devanagari. Keep the polite "आप" — Hindi app copy uses '
        '"आप" across audiences; "तू" would read as rude, not young. The modern feel comes '
        'from warmth, brevity, and natural English loanwords (e.g. "budget"), not informal '
        "pronouns."
    ),
    "hr": "Croatian; natural phrasing, not calqued.",
    "hu": "Hungarian; avoid stiff or bureaucratic register.",
    "id": "Indonesian as used in popular consumer apps.",
    "it": (
        'Informal "tu" (standard for youth-oriented consumer apps). Natural Italian; '
        "avoid unnecessary anglicisms."
    ),
    "ja": (
        "Keep polite-friendly です/ます — Japanese app copy stays polite regardless of "
        "audience age; plain/casual form reads as off, not young. Get warmth through "
        "light, soft, approachable phrasing (Apple Japan's voice), not by dropping "
        "politeness; avoid stiff keigo."
    ),
    "ko": (
        "Use the polite-friendly 해요체 — Korean app copy stays polite across ages; plain "
        "반말 reads as wrong, not young. Warmth comes from clean, light phrasing and "
        "natural English loanwords (common in Korean tech), not from dropping politeness. "
        "Match Apple Korea's voice."
    ),
    "ms": "Malay as used in consumer apps.",
    "nb": "Informal, direct Norwegian (Bokmål) — the norm for consumer apps.",
    "nl": (
        'Use the informal "je" — standard for Dutch consumer apps, especially for younger '
        'audiences ("u" reads as formal/older). Modern, relaxed register.'
    ),
    "pl": (
        'Modern Polish for young adults — use the informal "Ty" (direct address) rather '
        'than formal "Pan/Pani". Friendly, natural, not stiff.'
    ),
    "pt-BR": (
        'Brazilian Portuguese; informal, warm "você" (the natural informal address in '
        "Brazil). Brazilian orthography and vocabulary."
    ),
    "pt-PT": (
        'European Portuguese; informal "tu" (standard in youth-oriented PT app copy; '
        '"você" reads as distant). European orthography and vocabulary; avoid '
        "Brazilian-specific terms."
    ),
    "ro": "Romanian; natural phrasing.",
    "ru": (
        'Use the informal "ты" — modern Russian app copy for young adults (Yandex, '
        'T-Bank lifestyle) uses "ты" to feel current and friendly. Natural, non-calque '
        "Russian."
    ),
    "sk": "Slovak; natural phrasing.",
    "sv": "Informal, direct Swedish — the norm for consumer apps.",
    "th": (
        "Polite, friendly Thai — keep the polite particles (ครับ/ค่ะ) Thai app copy uses "
        "across audiences; the modern feel comes from light, contemporary phrasing, not "
        "from dropping politeness."
    ),
    "tr": (
        'Modern Turkish for young adults; use the informal "sen" (standard in youth-oriented '
        'app copy; "siz" reads as formal/older). Friendly and natural.'
    ),
    "uk": "Ukrainian; natural phrasing, not calqued from Russian or English.",
    "vi": "Vietnamese as used in popular consumer apps.",
    "zh-Hans": (
        "Simplified Chinese, mainland China conventions. Concise, modern app tone; avoid "
        "Taiwan-specific vocabulary. Mainland copy is punchy and benefit-dense — short "
        "rhythms land well, but keep it calm and avoid exclamation-heavy hype."
    ),
    "zh-Hant": (
        "Traditional Chinese, Taiwan conventions. Concise, modern app tone; avoid "
        "mainland-specific vocabulary."
    ),
}


def compose_note(register: str, addendum: str = "", *, prefix: str = "") -> str:
    """Join optional prefix, register core, and a domain addendum into one prompt note."""
    body = register
    extra = addendum.strip()
    if extra:
        body = f"{body} {extra}"
    if prefix:
        return f"{prefix}{body}"
    return body
