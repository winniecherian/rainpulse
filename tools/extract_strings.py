"""Collect user-visible strings from Swift sources into String Catalog keys."""
import re, glob, json, sys

PATTERNS = [
    r'\bText\(\s*"((?:[^"\\]|\\.)*)"',
    r'\bLabel\(\s*"((?:[^"\\]|\\.)*)"',
    r'\bButton\(\s*"((?:[^"\\]|\\.)*)"',
    r'\bToggle\(\s*"((?:[^"\\]|\\.)*)"',
    r'\bSection\(\s*"((?:[^"\\]|\\.)*)"',
    r'\bPicker\(\s*"((?:[^"\\]|\\.)*)"',
    r'\bLink\(\s*"((?:[^"\\]|\\.)*)"',
    r'\bLabeledContent\(\s*"((?:[^"\\]|\\.)*)"',
    r'\bContentUnavailableView\(\s*"((?:[^"\\]|\\.)*)"',
    r'\.navigationTitle\(\s*"((?:[^"\\]|\\.)*)"',
    r'\.accessibilityLabel\(\s*"((?:[^"\\]|\\.)*)"',
    r'\bconfirmationDialog\(\s*"((?:[^"\\]|\\.)*)"',
    r'String\(localized:\s*"((?:[^"\\]|\\.)*)"',
    r'\.configurationDisplayName\(\s*"((?:[^"\\]|\\.)*)"',
    r'\.description\(\s*"((?:[^"\\]|\\.)*)"',
]
INTY = re.compile(r'Int\(|\.count\b|\b(mins|minutes|chance|now|closest|age|aqi|usAQI|count|n|days|hours|percent|v)\b$')

def to_key(s):
    def rep(m):
        expr = m.group(1).strip()
        return "%lld" if INTY.search(expr) else "%@"
    # \( ... ) with one level of nested parens
    return re.sub(r'\\\(((?:[^()]|\([^()]*\))*)\)', rep, s)

keys = {}
for f in glob.glob("RainPulse/**/*.swift", recursive=True) + glob.glob("RainPulseWidget/**/*.swift", recursive=True) + glob.glob("Shared/**/*.swift", recursive=True):
    src = open(f).read()
    for p in PATTERNS:
        for m in re.finditer(p, src):
            raw = m.group(1)
            if not raw.strip() or raw.startswith(("http", "mailto")) or re.fullmatch(r'[\W\d%@l]*', to_key(raw)):
                continue
            k = to_key(raw).replace('\\"', '"').replace("\\n", "\n")
            keys.setdefault(k, set()).add(f.split("/")[-1])
json.dump(sorted(keys), open(sys.argv[1] if len(sys.argv) > 1 else "/tmp/keys.json", "w"), ensure_ascii=False, indent=0)
print(len(keys), "strings")
