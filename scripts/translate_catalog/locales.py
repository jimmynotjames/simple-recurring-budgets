"""
Single source of truth for the target locale set.
These are the App Store storefront locales (BCP 47 / Apple identifier form).
Import LOCALES and LOCALE_NAMES from this module in other pipeline scripts.
"""

LOCALES: list[str] = [
    "ar",       # Arabic
    "bn",       # Bengali
    "ca",       # Catalan
    "cs",       # Czech
    "da",       # Danish
    "de",       # German
    "el",       # Greek
    "en-AU",    # English (Australia)
    "en-CA",    # English (Canada)
    "en-GB",    # English (United Kingdom)
    "es",       # Spanish (Spain)
    "es-MX",    # Spanish (Mexico)
    "fi",       # Finnish
    "fr",       # French (France)
    "fr-CA",    # French (Canada)
    "gu",       # Gujarati
    "he",       # Hebrew
    "hi",       # Hindi
    "hr",       # Croatian
    "hu",       # Hungarian
    "id",       # Indonesian
    "it",       # Italian
    "ja",       # Japanese
    "kn",       # Kannada
    "ko",       # Korean
    "ml",       # Malayalam
    "mr",       # Marathi
    "ms",       # Malay
    "nb",       # Norwegian Bokmål
    "nl",       # Dutch
    "or",       # Odia
    "pa",       # Punjabi
    "pl",       # Polish
    "pt-BR",    # Portuguese (Brazil)
    "pt-PT",    # Portuguese (Portugal)
    "ro",       # Romanian
    "ru",       # Russian
    "sk",       # Slovak
    "sl",       # Slovenian
    "sv",       # Swedish
    "ta",       # Tamil
    "te",       # Telugu
    "th",       # Thai
    "tr",       # Turkish
    "uk",       # Ukrainian
    "ur",       # Urdu
    "vi",       # Vietnamese
    "zh-Hans",  # Chinese (Simplified)
    "zh-Hant",  # Chinese (Traditional)
]

LOCALE_NAMES: dict[str, str] = {
    "ar":      "Arabic",
    "bn":      "Bengali",
    "ca":      "Catalan",
    "cs":      "Czech",
    "da":      "Danish",
    "de":      "German",
    "el":      "Greek",
    "en-AU":   "English (Australia)",
    "en-CA":   "English (Canada)",
    "en-GB":   "English (United Kingdom)",
    "es":      "Spanish (Spain)",
    "es-MX":   "Spanish (Mexico)",
    "fi":      "Finnish",
    "fr":      "French (France)",
    "fr-CA":   "French (Canada)",
    "gu":      "Gujarati",
    "he":      "Hebrew",
    "hi":      "Hindi",
    "hr":      "Croatian",
    "hu":      "Hungarian",
    "id":      "Indonesian",
    "it":      "Italian",
    "ja":      "Japanese",
    "kn":      "Kannada",
    "ko":      "Korean",
    "ml":      "Malayalam",
    "mr":      "Marathi",
    "ms":      "Malay",
    "nb":      "Norwegian Bokmål",
    "nl":      "Dutch",
    "or":      "Odia",
    "pa":      "Punjabi",
    "pl":      "Polish",
    "pt-BR":   "Portuguese (Brazil)",
    "pt-PT":   "Portuguese (Portugal)",
    "ro":      "Romanian",
    "ru":      "Russian",
    "sk":      "Slovak",
    "sl":      "Slovenian",
    "sv":      "Swedish",
    "ta":      "Tamil",
    "te":      "Telugu",
    "th":      "Thai",
    "tr":      "Turkish",
    "uk":      "Ukrainian",
    "ur":      "Urdu",
    "vi":      "Vietnamese",
    "zh-Hans": "Chinese (Simplified)",
    "zh-Hant": "Chinese (Traditional)",
}
