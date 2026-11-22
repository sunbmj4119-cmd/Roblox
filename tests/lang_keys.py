"""
Extracts every player-facing English string (translation key) from the code
and Config, and checks that src/shared/LangKO.luau has a Korean entry for each.

    python3 tests/lang_keys.py          # report missing keys (exit 1 if any)
    python3 tests/lang_keys.py --list   # print all keys
"""
import glob
import re
import sys

ROOT = __file__.rsplit("/tests/", 1)[0]
STR = r'"((?:[^"\\]|\\.)*)"'


def unescape(s):
    return s.encode("utf-8").decode("unicode_escape").encode("latin-1").decode("utf-8")


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


keys = set()


def add(s):
    s = unescape(s)
    if not s or not re.search(r"[A-Za-z]{2,}", s):
        return
    keys.add(s)


client = glob.glob(ROOT + "/src/client/**/*.luau", recursive=True)
server = glob.glob(ROOT + "/src/server/**/*.luau", recursive=True)
skip_files = ("DevTools.luau", "DevService.luau")

for path in client + server:
    if path.endswith(skip_files):
        continue
    src = read(path)
    # explicit translation calls
    for m in re.finditer(r"(?:\bT|Lib\.T|Lang\.T)\(\s*" + STR, src):
        add(m.group(1))
    for m in re.finditer(r"Net:(?:Notify|L)\(\s*[\w.]+\s*,\s*" + STR, src):
        add(m.group(1))
    for m in re.finditer(r"Net:Announce\(\s*" + STR, src):
        add(m.group(1))
    for m in re.finditer(r"GrantReward\([^\n]*?,\s*" + STR, src):
        add(m.group(1))
    for m in re.finditer(r"SetText\([^,\n]+,\s*" + STR, src):
        add(m.group(1))
    for m in re.finditer(r"\bbillboard\([^,\n]+,\s*" + STR, src):
        add(m.group(1))
    for m in re.finditer(r"\bbooth\([^,\n]+,\s*" + STR, src):
        add(m.group(1))
    for m in re.finditer(r"\bsign\([^,\n]+,\s*" + STR, src):
        add(m.group(1))
    for m in re.finditer(r"\bprompt\([^,\n]+,\s*" + STR + r"\s*,\s*(?:" + STR + r")?", src):
        add(m.group(1))
        if m.group(2):
            add(m.group(2))
    # static UI text that Lib.Text / Lib.Button / SetButton auto-translate
    if "/client/" in path:
        for m in re.finditer(r"\bText\s*=\s*(?:if [^\n]*?then\s*)?" + STR, src):
            add(m.group(1))
        for m in re.finditer(r"\bText\s*=\s*if [^\n]*?then\s*" + STR + r"\s*else\s*" + STR, src):
            add(m.group(1))
            add(m.group(2))
        for m in re.finditer(r"SetButton\([^\n]*", src):
            for s in re.findall(STR, m.group(0)):
                add(s)
        for m in re.finditer(r"Title\s*=\s*" + STR, src):
            add(m.group(1))
        for m in re.finditer(r"wideCard\([^\n]*", src):
            for s in re.findall(STR, m.group(0)):
                add(s)
        for m in re.finditer(r"labels\s*=\s*\{[^}]*\}", src):
            for s in re.findall(STR, m.group(0)):
                add(s)
        for m in re.finditer(r"\{\s*\"\w+\",\s*\"[^\"]*\",\s*" + STR, src):  # MENU / DEFS tables
            add(m.group(1))
        for m in re.finditer(r"Title\s*=\s*" + STR, src):
            add(m.group(1))
    # server-side returned messages
    if "/server/" in path:
        for m in re.finditer(r"return false,\s*" + STR, src):
            add(m.group(1))
        for m in re.finditer(r"CURRENCY_NAMES = \{[^}]*\}", src):
            for s in re.findall(STR, m.group(0)):
                add(s)
        for m in re.finditer(r"notEnough\([^\n]*", src):
            for s in re.findall(STR, m.group(0)):
                add(s)

# Config strings shown to players
config = read(ROOT + "/src/shared/Config.luau")
for field in ("Name", "Description", "Text", "Tag", "Title", "PriceText"):
    for m in re.finditer(r"\b" + field + r"\s*=\s*" + STR, config):
        add(m.group(1))
for m in re.finditer(r'\[\s*' + STR + r'\s*\]\s*=\s*\{\s*Rarity', config):  # pet names in ["..."]
    add(m.group(1))
for m in re.finditer(r'^\t(\w+) = \{ Rarity', config, re.M):  # Bunny = { Rarity ...
    add(m.group(1))
for m in re.finditer(r'^\t(Common|Uncommon|Rare|Epic|Legendary|Mythic|Secret) =', config, re.M):
    add(m.group(1))
for m in re.finditer(r'Id = "(Golden|Rainbow)"', config):
    add(m.group(1))
for m in re.finditer(r'Pet = ' + STR, config):
    add(m.group(1))
util = read(ROOT + "/src/shared/Util.luau")
for m in re.finditer(r"translate\(" + STR, util):
    add(m.group(1))
for m in re.finditer(r'BOOST_NAMES = \{[^}]*\}', util):
    for s in re.findall(STR, m.group(0)):
        add(s)
amb = read(ROOT + "/src/client/Controllers/Ambience.luau")
for m in re.finditer(r"Title\s*=\s*" + STR, amb):
    add(m.group(1))
# brand name is never translated
keys.discard("Meteor Miners")

ko = read(ROOT + "/src/shared/LangKO.luau")
pairs = {
    unescape(m.group(1)): unescape(m.group(2))
    for m in re.finditer(r'^\t\[' + STR + r'\]\s*=\s*' + STR + r',', ko, re.M)
}
have = set(pairs)

# Korean text must keep the same format specifiers in the same order
SPEC = re.compile(r"%[-+ #0]*\d*(?:\.\d+)?[sdifxXq%]")
bad = [k for k, v in pairs.items() if SPEC.findall(k) != SPEC.findall(v)]
for k in bad:
    print("PLACEHOLDER MISMATCH:", repr(k), "->", repr(pairs[k]))

if "--list" in sys.argv:
    for k in sorted(keys):
        print(k)
    sys.exit(0)

missing = sorted(k for k in keys if k not in have)
for k in missing:
    print("MISSING:", k)
print(f"{len(keys)} keys, {len(missing)} missing, {len(pairs)} translations, {len(bad)} placeholder mismatches")
sys.exit(1 if missing or bad else 0)
