"""Lists every tr('...') text in lib/ that has no Arabic in lib/l10n/strings_ar.dart,
and every Arabic entry that is no longer used. Run:  python3 tools/check_translations.py"""
import re, sys, glob, os

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
used = set()
for f in glob.glob(os.path.join(root, "lib", "**", "*.dart"), recursive=True):
    if f.endswith("strings_ar.dart"):
        continue
    src = open(f, encoding="utf-8").read()
    for m in re.finditer(r"tr\(\s*'((?:[^'\\]|\\.)*)'", src):
        used.add(m.group(1).replace("\\'", "'").replace("\\n", "\n"))
# texts passed through a variable (settings screen corner names)
used |= {"Top left", "Top right", "Bottom left", "Bottom right"}

ar_src = open(os.path.join(root, "lib", "l10n", "strings_ar.dart"), encoding="utf-8").read()
have = set()
for m in re.finditer(r"^\s*'((?:[^'\\]|\\.)*)'\s*:", ar_src, re.M):
    have.add(m.group(1).replace("\\'", "'").replace("\\n", "\n"))

missing = sorted(used - have)
unused = sorted(have - used)
for t in missing:
    print("MISSING:", t)
for t in unused:
    print("unused :", t)
print(f"\n{len(used)} texts, {len(missing)} missing, {len(unused)} unused")
sys.exit(1 if missing else 0)
