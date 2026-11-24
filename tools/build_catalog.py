import json, re, glob
LANGS = ["es", "pt-BR", "hi", "id", "ja", "de", "fr", "ar", "ta", "vi"]
keys = json.load(open("/tmp/tkeys.json"))
rows = {}
for f in sorted(glob.glob("tools/i18n/part*.tsv")):
    for line in open(f, encoding="utf-8"):
        if line.startswith("#") or not line.strip("\n"): continue
        parts = line.rstrip("\n").split("\t")
        assert len(parts) == 11, (f, parts[0], len(parts))
        rows[int(parts[0])] = parts[1:]
def specs(s):
    out = []
    for m in re.finditer(r'%(?:(\d+)\$)?(lld|@|%)', s):
        if m.group(2) != "%": out.append(m.group(2))
    return sorted(out)
bad = 0
cat = {"sourceLanguage": "en", "strings": {}, "version": "1.0"}
for i, k in enumerate(keys):
    entry = {}
    if i in rows:
        loc = {}
        for lang, val in zip(LANGS, rows[i]):
            # Same placeholders, in the SAME ORDER, and no positional (%1$@) forms: iOS 27's
            # strict format checking rejects reordered arguments at runtime.
            order = lambda x: re.findall(r'%(?:lld|@)', x)
            if order(val) != order(k) or "$" in val or val.count("%%") != k.count("%%"):
                print("PLACEHOLDER MISMATCH", i, lang, repr(k), repr(val)); bad += 1; continue
            loc[lang] = {"stringUnit": {"state": "translated", "value": val}}
        entry["localizations"] = loc
    cat["strings"][k] = entry
missing = [i for i in range(len(keys)) if i not in rows]
print("translated", len(rows), "of", len(keys), "missing idx", missing, "bad", bad)
json.dump(cat, open("Shared/Localizable.xcstrings", "w"), ensure_ascii=False, indent=2, sort_keys=True)
