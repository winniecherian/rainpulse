"""Merge tools/i18n/extra.py into Shared/Localizable.xcstrings (keyed by English text).
Checks every translation keeps the English placeholders in the same order (iOS 27 is strict)."""
import json, re, sys
sys.path.insert(0, "tools/i18n")
from extra import T
LANGS = ["es", "pt-BR", "hi", "id", "ja", "de", "fr", "ar", "ta", "vi"]
order = lambda x: re.findall(r'%(?:lld|@|lf)', x)
path = "Shared/Localizable.xcstrings"
cat = json.load(open(path, encoding="utf-8"))
bad = 0
for key, vals in T.items():
    assert len(vals) == len(LANGS), key
    loc = {}
    for lang, val in zip(LANGS, vals):
        if order(val) != order(key) or "$" in val or "\t" in val:
            print("PLACEHOLDER MISMATCH", lang, repr(key), repr(val)); bad += 1; continue
        loc[lang] = {"stringUnit": {"state": "translated", "value": val}}
    cat["strings"].setdefault(key, {})["localizations"] = loc
json.dump(cat, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=2, sort_keys=True)
print("merged", len(T), "strings; bad", bad)
sys.exit(1 if bad else 0)
