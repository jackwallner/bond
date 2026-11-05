#!/usr/bin/env python3
"""Checks Shared/Localizable.xcstrings against the Swift source.

Run from the repo root: python3 Tools/Localization/check.py

Fails (exit 1) when
  * a localizable literal in the source has no catalog key,
  * a screen-bound `return "..."`, switch arm or ternary of literals skips the catalog,
  * a catalog key is missing a language listed in LANGS,
  * a translation's format specifiers do not match its key,
  * an English plural form or substitution is malformed,
  * a language lacks a plural category its grammar needs (PLURAL_CATEGORIES),
  * a template or starter chip's stable English text has no catalog key,
  * a literal is passed to a helper that takes an unlabeled String and renders it, or
  * an Info.plist purpose string has no InfoPlist.xcstrings entry.

Literals count as localizable when they are the first argument of a SwiftUI
text API (Text, Button, Label, Section, navigationTitle, alert, ...) or of
String(localized:). Interpolations are compared loosely (%@ and %lld match
each other), because the type of an interpolated expression is not visible
without the compiler.

Mark a line `// l10n-ignore` when a literal is deliberately not copy.
"""
import json
import os
import plistlib
import re
import sys

ROOT = os.getcwd()
DIRS = ['Bond', 'Shared', 'BondWatch', 'BondWidgets']
CATALOG = os.path.join('Shared', 'Localizable.xcstrings')
# Info.plist -> InfoPlist.xcstrings that must hold its purpose strings.
PLISTS = {
    'Bond/Info.plist': 'Bond/InfoPlist.xcstrings',
    'BondWatch/Info.plist': 'BondWatch/InfoPlist.xcstrings',
    'BondWidgets/Info.plist': 'BondWidgets/InfoPlist.xcstrings',
}
LANGS = ['fr', 'pt-BR', 'es', 'ar', 'de', 'vi', 'ru']
# CLDR plural categories each shipping language must provide in every plural
# variation. Arabic needs all six: zero and two must never collapse to other.
PLURAL_CATEGORIES = {
    'ar': {'zero', 'one', 'two', 'few', 'many', 'other'},
    'ru': {'one', 'few', 'many', 'other'},
    'fr': {'one', 'many', 'other'},
    'pt-BR': {'one', 'many', 'other'},
    'es': {'one', 'many', 'other'},
    'de': {'one', 'other'},
    'vi': {'other'},
}
# Files whose `title:` / `body:` literals are stable English that is also a
# catalog key (the text is persisted; screens look the key up to display it).
KEYED_ARG_FILES = {
    'Shared/Models/ReminderTemplate.swift': 'TemplateReminder(',
    'Bond/Features/ReminderList/EmptyRemindersView.swift': 'StarterChip(',
}
KEYED_ARG = re.compile(r'\b(?:title|body):\s*"((?:[^"\\]|\\.)*)"')
HELPER_DEF = re.compile(r'\bfunc\s+(\w+)\(_\s+\w+:\s*String\b')
# DEBUG-only fixtures and analytics: never reach a user's screen.
SKIP_FILES = {
    'Bond/Utilities/BondScreenshotSeed.swift',
    'Bond/Views/PaywallScreenshotHarness.swift',
    'Bond/Services/ConversionDiagnostics.swift',
}
UI_FUNCS = {'Text', 'Button', 'Label', 'Section', 'Toggle', 'TextField', 'navigationTitle', 'accessibilityLabel',
            'alert', 'DatePicker', 'Stepper', 'Link', 'configurationDisplayName', 'description',
            'confirmationDialog', 'Picker', 'LocalizedStringKey', 'accessibilityHint', 'SecureField',
            'ContentUnavailableView', 'ProgressView', 'LabeledContent', 'value'}
IGNORED = {'0'}
# A literal is copy when it has a space or is a single capitalised word.
COPY = re.compile(r'\s|^[A-Z][a-z]+[!.?]?$')
ARM = re.compile(r'^\s*(?:case\b[^:]*:|default:)\s*(?:return\s+)?"((?:[^"\\]|\\.)*)"\s*$')
RETURN = re.compile(r'\breturn\s+"((?:[^"\\]|\\.)*)"')
TERNARY = re.compile(r'\?\s*"((?:[^"\\]|\\.)*)"\s*:\s*"((?:[^"\\]|\\.)*)"')
MESSAGE = re.compile(r'\b\w*(?:[eE]rror|[mM]essage|[sS]tatus)\w*\s*=\s*"((?:[^"\\]|\\.)*)"')


def parse_literal(src, i):
    """src[i] == '"'. Returns (end_index_after, segments) where segments are ('lit', str) or ('interp', expr)."""
    assert src[i] == '"'
    if src.startswith('"""', i):
        j = src.index('"""', i + 3)
        return j + 3, None
    i += 1
    segs = []
    buf = ''
    while True:
        c = src[i]
        if c == '"':
            if buf:
                segs.append(('lit', buf))
            return i + 1, segs
        if c == '\\':
            n = src[i + 1]
            if n == '(':
                if buf:
                    segs.append(('lit', buf))
                    buf = ''
                depth = 1
                j = i + 2
                expr = ''
                while depth:
                    ch = src[j]
                    if ch == '"':
                        k, _ = parse_literal(src, j)
                        expr += src[j:k]
                        j = k
                        continue
                    if ch == '(':
                        depth += 1
                    elif ch == ')':
                        depth -= 1
                        if depth == 0:
                            break
                    expr += ch
                    j += 1
                segs.append(('interp', expr.strip()))
                i = j + 1
                continue
            if n == 'u':
                j = src.index('}', i)
                buf += chr(int(src[i + 3:j], 16))
                i = j + 1
                continue
            buf += {'n': '\n', 't': '\t', '"': '"', '\\': '\\', "'": "'", '0': '\0'}[n]
            i += 2
            continue
        buf += c
        i += 1


def scan(path):
    src = open(path).read()
    out = []
    stack = []  # (funcname, argtext_since_last_comma, argindex)
    i = 0
    n = len(src)
    line = 1
    while i < n:
        c = src[i]
        if c == '\n':
            line += 1
        if src.startswith('//', i):
            j = src.find('\n', i)
            i = n if j < 0 else j
            continue
        if src.startswith('/*', i):
            j = src.index('*/', i)
            line += src[i:j].count('\n')
            i = j + 2
            continue
        if c == '"':
            end, segs = parse_literal(src, i)
            if segs is not None and stack:
                fn, argtxt, idx = stack[-1]
                ctx = None
                if fn == 'String' and argtxt.strip().startswith('localized:'):
                    ctx = 'String'
                elif fn in UI_FUNCS and idx == 0 and not re.match(r'\s*[a-zA-Z_]+\s*:', argtxt):
                    ctx = fn
                elif fn in UI_FUNCS and idx == 0 and re.match(r'\s*titleKey\s*:', argtxt):
                    ctx = fn
                if ctx:
                    out.append((line, ctx, segs))
            line += src[i:end].count('\n')
            if stack:
                f, a, k = stack[-1]
                stack[-1] = (f, a + src[i:end], k)
            i = end
            continue
        if c == '(':
            m = re.search(r'([A-Za-z_][A-Za-z_0-9]*)\s*$', src[max(0, i - 60):i])
            stack.append((m.group(1) if m else '', '', 0))
            i += 1
            continue
        if c == ')':
            if stack:
                stack.pop()
            i += 1
            continue
        if c == ',' and stack:
            f, a, k = stack[-1]
            stack[-1] = (f, '', k + 1)
            i += 1
            continue
        if stack:
            f, a, k = stack[-1]
            stack[-1] = (f, a + c, k)
        i += 1
    return out


def loose(key):
    return re.sub(r'%(\d+\$)?(lld|@)', '%*', key)


def specs(value, subs=None):
    found = []
    auto = 0
    for m in re.finditer(r'%(?:(\d+)\$)?(lld|@|%)|%#@(\w+)@', value):
        if m.group(2) == '%':
            continue
        if m.group(3):
            found.append((subs[m.group(3)]['argNum'], 'lld'))
            continue
        if m.group(1):
            pos = int(m.group(1))
        else:
            auto += 1
            pos = auto
        found.append((pos, m.group(2)))
    return sorted(set(found))


def leaks(path):
    """Unwrapped copy that reaches the screen: return, switch arm, ternary, error/status assignment."""
    found = []
    for number, text in enumerate(open(path).read().split('\n'), 1):
        code = text.split('//')[0] if '"' not in text.split('//')[0][-1:] else text
        if 'l10n-ignore' in text or 'String(localized' in code or 'log.' in code:
            continue
        hits = []
        for rx in (RETURN, MESSAGE):
            hits += [m.group(1) for m in rx.finditer(code)]
        arm = ARM.match(code)
        if arm:
            hits.append(arm.group(1))
        for m in TERNARY.finditer(code):
            hits += [m.group(1), m.group(2)]
        for literal in hits:
            if COPY.search(literal):
                found.append(f'{path}:{number}: copy bypasses the catalog: "{literal}" (use String(localized:))')
                break
    return found


def keyed_args(rel, catalog, problems):
    marker = KEYED_ARG_FILES.get(rel)
    if not marker:
        return
    for number, text in enumerate(open(os.path.join(ROOT, rel)).read().split('\n'), 1):
        if marker not in text or 'l10n-ignore' in text:
            continue
        for m in KEYED_ARG.finditer(text):
            if m.group(1) not in catalog:
                problems.append(f'{rel}:{number}: no catalog key for stable text "{m.group(1)}"')


def helper_literals(files, problems):
    """A helper taking an unlabeled String renders it verbatim, so a literal passed to it skips the catalog."""
    names = set()
    sources = {}
    for rel in files:
        sources[rel] = open(os.path.join(ROOT, rel)).read()
        names |= set(HELPER_DEF.findall(sources[rel]))
    for rel, src in sources.items():
        for number, text in enumerate(src.split('\n'), 1):
            code = text.split('//')[0]
            if 'l10n-ignore' in text or 'func ' in code:
                continue
            for m in re.finditer(r'\b(\w+)\(\s*"((?:[^"\\]|\\.)*)"', code):
                if m.group(1) in names and COPY.search(m.group(2)):
                    problems.append(f'{rel}:{number}: "{m.group(2)}" passed to {m.group(1)}(_: String) skips the catalog (use String(localized:))')


def check_plurals(catalog, problems):
    for lang in LANGS:
        need = PLURAL_CATEGORIES.get(lang)
        if need is None:
            problems.append(f'check.py: add {lang} to PLURAL_CATEGORIES')
            continue
        for key, entry in catalog.items():
            plural = entry.get('localizations', {}).get(lang, {}).get('variations', {}).get('plural')
            if plural is None:
                continue
            missing = need - set(plural)
            if missing:
                problems.append(f'"{key}" [{lang}]: plural lacks {", ".join(sorted(missing))}')


def check_plist(rel, catalog_rel, problems):
    path = os.path.join(ROOT, rel)
    if not os.path.exists(path):
        return
    info = plistlib.load(open(path, 'rb'))
    wanted = [k for k in info if k.endswith('UsageDescription')]
    if not wanted:
        return
    try:
        strings = json.load(open(os.path.join(ROOT, catalog_rel)))['strings']
    except OSError:
        problems.append(f'{rel}: no {catalog_rel}')
        return
    for key in wanted:
        entry = strings.get(key)
        if entry is None:
            problems.append(f'{catalog_rel}: missing {key}')
            continue
        for lang in ['en'] + LANGS:
            if lang not in entry.get('localizations', {}):
                problems.append(f'{catalog_rel}: "{key}" missing {lang}')


def check_values(key, entry, langs, problems):
    locs = entry.get('localizations', {})
    for lang in langs:
        loc = locs.get(lang)
        if loc is None:
            if lang != 'en':
                problems.append(f'"{key}": missing {lang}')
            continue
        want = specs(key)
        if 'variations' in loc:
            values = [u['stringUnit']['value'] for u in loc['variations']['plural'].values()]
            bad = [v for v in values if specs(v) and specs(v) != want]
        else:
            bad = [] if specs(loc['stringUnit']['value'], loc.get('substitutions')) == want else [loc['stringUnit']['value']]
        for v in bad:
            problems.append(f'"{key}" [{lang}]: format specifiers differ in "{v}"')
    for lang, loc in locs.items():
        units = [loc] + list(loc.get('variations', {}).get('plural', {}).values())
        for unit in units:
            value = unit.get('stringUnit', {}).get('value', '')
            for name in re.findall(r'%(?:\d+\$)?#@(\w+)@', value):
                if name not in loc.get('substitutions', {}):
                    problems.append(f'"{key}" [{lang}]: plural token {name!r} has no substitution')


def main():
    data = json.load(open(os.path.join(ROOT, CATALOG)))
    catalog = data['strings']
    by_loose = {loose(k): k for k in catalog}
    problems = []
    if data.get('sourceLanguage') != 'en':
        problems.append('catalog sourceLanguage must be en')
    for key, entry in catalog.items():
        if entry.get('extractionState') != 'manual':
            problems.append(f'"{key}": extractionState must be manual')
    swift_files = []
    for d in DIRS:
        for dirpath, _, files in os.walk(os.path.join(ROOT, d)):
            for name in files:
                if not name.endswith('.swift'):
                    continue
                path = os.path.join(dirpath, name)
                rel = os.path.relpath(path, ROOT)
                if rel in SKIP_FILES:
                    continue
                swift_files.append(rel)
                keyed_args(rel, catalog, problems)
                for line, _, segs in scan(path):
                    has_interp = any(kind == 'interp' for kind, _ in segs)
                    key = ''.join((v.replace('%', '%%') if has_interp else v) if kind == 'lit' else '%@'
                                  for kind, v in segs)
                    bare = key.strip() and not re.search(r'[A-Za-z]', key.replace('%@', '').replace('%lld', ''))
                    if key.strip() and not bare and key not in IGNORED and loose(key) not in by_loose:
                        problems.append(f'{rel}:{line}: no catalog key for "{key}"')
                problems += leaks(rel)
    helper_literals(swift_files, problems)
    check_plurals(catalog, problems)
    for key, entry in catalog.items():
        check_values(key, entry, ['en'] + LANGS, problems)
    for rel, catalog_rel in PLISTS.items():
        check_plist(rel, catalog_rel, problems)
    for p in problems:
        print(p)
    print(f'{len(catalog)} keys, {len(LANGS)} languages, {len(problems)} problems')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
