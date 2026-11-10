#!/usr/bin/env python3
"""Localization lint for Dynamic Caffe Island.

Compares the strings the Swift compiler extracted from the app
(`*.stringsdata`, produced by a build with SWIFT_EMIT_LOC_STRINGS=YES) with
the String Catalogs in App/, and reports for every language:

  - keys used in code but missing from the catalog  (→ add them)
  - keys in the catalog no longer used in code      (→ stale, remove)
  - keys missing a translation / not "translated"   (→ translate)
  - format placeholders (%@, %lld, ${name}) that differ from the source

Usage:
  xcodebuild … build                       # any build of the app target
  python3 scripts/i18n-check.py [DERIVED_DATA_DIR]

Exits non-zero when anything needs attention, so CI can gate on it.
"""
import glob
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DERIVED = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "dd")
CATALOGS = {"Localizable": "App/Localizable.xcstrings"}
# Siri/Spotlight phrases: .strings per language (String Catalog needs macOS 14).
SHORTCUTS_SOURCE = "App/en.lproj/AppShortcuts.strings"
STRINGS_LINE = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;', re.M)
PLACEHOLDER = re.compile(r"%(?:\d+\$)?[@dilfsu]|%(?:\d+\$)?ll[du]|\$\{[A-Za-z]+\}")

STRICT_TABLES = {"Localizable"}


def read_strings(path):
    with open(path, encoding="utf-8") as fh:
        return dict(STRINGS_LINE.findall(fh.read()))


def check_shortcuts():
    problems = 0
    source = read_strings(os.path.join(ROOT, SHORTCUTS_SOURCE))
    print(f"\n== AppShortcuts.strings  ({len(source)} phrases)")
    for k in source:
        if "${applicationName}" not in k:
            print(f"  SOURCE phrase lacks ${{applicationName}}: {k!r}"); problems += 1
    for path in sorted(glob.glob(os.path.join(ROOT, "App", "*.lproj", "AppShortcuts.strings"))):
        lang = os.path.basename(os.path.dirname(path)).split(".")[0]
        if path.endswith(SHORTCUTS_SOURCE):
            continue
        tr = read_strings(path)
        for k in source:
            v = tr.get(k)
            if not v:
                print(f"  [{lang}] UNTRANSLATED phrase: {k!r}"); problems += 1
            elif sorted(PLACEHOLDER.findall(v)) != sorted(PLACEHOLDER.findall(k)):
                print(f"  [{lang}] PLACEHOLDER MISMATCH: {k!r} → {v!r}"); problems += 1
        for k in set(tr) - set(source):
            print(f"  [{lang}] STALE phrase: {k!r}"); problems += 1
    return problems


def extracted_keys():
    keys = {}
    pattern = os.path.join(DERIVED, "Build", "Intermediates.noindex", "DynamicCaffeIsland.build", "*", "DynamicCaffeIsland.build", "Objects-normal", "*", "*.stringsdata")
    files = glob.glob(pattern)
    if not files:
        sys.exit(f"no .stringsdata under {DERIVED} — build the app first (SWIFT_EMIT_LOC_STRINGS=YES)")
    for f in files:
        with open(f, encoding="utf-8") as fh:
            data = json.load(fh)
        for table, entries in data.get("tables", {}).items():
            keys.setdefault(table, set()).update(e["key"] for e in entries)
    return keys


def main():
    used = extracted_keys()
    problems = 0
    for table, rel in CATALOGS.items():
        with open(os.path.join(ROOT, rel), encoding="utf-8") as fh:
            cat = json.load(fh)
        strings = cat["strings"]
        langs = sorted({lang for e in strings.values() for lang in e.get("localizations", {})} - {cat["sourceLanguage"]})
        in_code = used.get(table, set())
        print(f"\n== {rel}  ({len(strings)} keys, languages: {', '.join(langs) or 'none'})")

        if table in STRICT_TABLES:
            for k in sorted(in_code - set(strings)):
                print(f"  MISSING in catalog: {k!r}"); problems += 1
            for k in sorted(set(strings) - in_code):
                print(f"  STALE (unused):     {k!r}"); problems += 1

        for k, e in sorted(strings.items()):
            if e.get("shouldTranslate") is False:
                continue
            src_ph = sorted(PLACEHOLDER.findall(k))
            for lang in langs:
                unit = e.get("localizations", {}).get(lang, {}).get("stringUnit")
                if not unit or unit.get("state") != "translated" or not unit.get("value"):
                    print(f"  [{lang}] UNTRANSLATED: {k!r}"); problems += 1
                    continue
                if sorted(PLACEHOLDER.findall(unit["value"])) != src_ph:
                    print(f"  [{lang}] PLACEHOLDER MISMATCH: {k!r} → {unit['value']!r}"); problems += 1

    problems += check_shortcuts()
    print("\nOK — all strings localized." if problems == 0 else f"\n{problems} issue(s).")
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
