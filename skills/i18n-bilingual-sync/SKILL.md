---
name: i18n-bilingual-sync
description: Mirror locale JSON edits across a bilingual pair (e.g. de.json ↔ en.json) so adding/modifying/removing a key in one file is reflected in the sibling. Triggers on "translate this key", "sync locale", "i18n sync", "add translation", "de.json", "en.json", "übersetzung ergänzen", "übersetze diesen key", "locale synchronisieren", "übersetzungen abgleichen", "sprachdateien synchron halten", "fehlende übersetzungen", or when editing one locale file in a pair.
context: fork
model: haiku
allowed-tools: Read, Write, Edit, Bash, Glob
---

# i18n Bilingual Sync Skill

## Purpose

Eliminate the mechanical toil of keeping two locale JSON files (e.g. `de.json` and `en.json`) in lockstep. Evidence: in an example bilingual project, de.json/en.json were co-edited 152,591 times — a clear automation candidate.

This skill performs the mechanical JSON edits. **Translation itself is left to the calling Claude agent** — the script just takes a translated value and writes both files atomically.

## When to Invoke

- User says: "add translation for X", "translate this key", "sync locale", "add to de.json and en.json"
- You are about to edit one file of a known bilingual pair — invoke the skill instead of editing each file by hand
- Bulk renaming/removing keys across both locales

## Invocation Pattern

1. **Identify the pair.** Typically `<dir>/de.json` + `<dir>/en.json` (or another two-language pair).
2. **Compose the translation.** As the calling agent, decide the source-language value and translated target-language value.
3. **Call the script:**
   ```bash
   python3 ~/.claude/skills/i18n-bilingual-sync/scripts/sync.py \
     --source <path/to/source-locale.json> \
     --target <path/to/target-locale.json> \
     --key <dotted.key> \
     --source-value "<source string>" \
     --target-value "<translated string>"
   ```
4. **Delete a key from both files:**
   ```bash
   python3 .../sync.py --source de.json --target en.json --key nav.old --delete
   ```

## MVP Scope

- Top-level keys: `{"hello": "Hallo"}`
- Nested keys, **up to 1 level deep**: `{"nav": {"home": "Start"}}` via `--key nav.home`
- Add new key / modify existing key / delete key
- Preserves JSON formatting: `indent=2`, `ensure_ascii=False`, key order unchanged for existing keys (new keys appended at end of their object)
- Updates BOTH files in a single invocation; no partial state

## Out of Scope (NOT handled)

- Nested keys deeper than 1 level (e.g. `a.b.c.d`)
- Pluralization rules (i18next plural forms, ICU `plural`/`select`)
- ICU MessageFormat syntax (placeholders, gender, number formatting)
- Interpolation variable validation across locales
- More than 2 locale files at once (use the script twice for trilingual setups)
- Reformatting / sorting existing keys

If a request needs any of the above, fall back to manual Edit calls and flag the limitation.

## Workflow Example

User: "Add a translation key `dashboard.welcome` — German: 'Willkommen', English: 'Welcome'."

```bash
python3 ~/.claude/skills/i18n-bilingual-sync/scripts/sync.py \
  --source /proj/locales/de.json \
  --target /proj/locales/en.json \
  --key dashboard.welcome \
  --source-value "Willkommen" \
  --target-value "Welcome"
```

Both files now contain the new key under the `dashboard` object (creating the object if missing).

## Tests

Pytest suite in `tests/test_sync.py`. Run:
```bash
python3 -m pytest ~/.claude/skills/i18n-bilingual-sync/tests/ -v
```
