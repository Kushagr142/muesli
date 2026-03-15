# Context Handover — Personal Dictionary Custom Word Correction

**Session Date:** 2026-03-15
**Repository:** muesli
**Branch:** `main`

---

## Task

Add a Personal Dictionary feature — a sidebar tab where users add custom words/replacement pairs. After Whisper transcribes, a local post-processing step fuzzy-matches transcribed words against the dictionary and corrects them. Two-stage matching: phonetic pre-filter (Metaphone) + Jaro-Winkler similarity. <1ms overhead, no model needed.

## Full Implementation Plan

See `/Users/pranavhari/.claude/plans/lively-mapping-tower.md` for the approved, detailed plan covering all 11 files.

## Quick Reference

**New file:** `DictionaryView.swift` — SwiftUI view with word list, add/delete, "from → to" pairs

**Key changes:**
- `Models.swift`: Add `CustomWord` struct + `customWords: [CustomWord]` to AppConfig
- `AppState.swift`: Add `.dictionary` to DashboardTab
- `SidebarView.swift` + `DashboardRootView.swift`: Wire new tab
- `MuesliController.swift`: `addCustomWord()`, `removeCustomWord()`, pass words to transcription
- `bridge/worker.py`: `_apply_custom_words()` with Metaphone + Jaro-Winkler via `jellyfish` package
- `PythonWorkerClient.swift` + async wrapper + `TranscriptionRuntime.swift`: Thread `custom_words` param
- `scripts/bundle_python.sh`: Add `jellyfish` to essential packages

**Install jellyfish first:** `.venv/bin/pip install jellyfish`

**Design reference:** WisprFlow's Dictionary tab screenshot in conversation — word list with "Add new" button, shows single words and "from → to" replacement pairs.
