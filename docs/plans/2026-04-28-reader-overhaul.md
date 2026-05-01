# Reader Overhaul — Production-Grade E-Reader + Tap-to-RSVP

**Created:** 2026-04-28
**Status:** Live working doc — update across sessions
**Owner:** <operator-email>

This document captures the current state and direction of the reading experience in SpeedRead. It is the source of truth for cross-session work on the reader, format support, and the reader↔RSVP handoff. Update when scope, decisions, or architecture change.

---

## 1 · Goals

1. **First-class file import.** Drag any reading material from desktop → iPhone Files → SpeedRead and start reading.
2. **Production-quality reader view.** Looks and feels like Apple Books / Kindle / Readwise: typography, theming, progress, navigation, comfortable reading at length.
3. **Seamless reader ↔ RSVP handoff.** Tap any word in the reader → RSVP launches at that exact word. When RSVP dismisses, the last word shown is highlighted red in the reader and is scrolled into view.
4. **Useful for both novices and experienced speed readers.** Defaults work out-of-the-box; power features (WPM curve, ORP, scrub) stay accessible.

## 2 · Supported Formats

### Currently supported
- **PDF** — `PDFExtractor` via PDFKit. Pulls per-page text + title/author metadata.
- **EPUB 2/3** — `EPUBExtractor` with pure-Swift ZIP reader (Compression framework). Parses container.xml → OPF → spine, strips XHTML, preserves paragraph breaks via block-tag → newline substitution.

### Adding now
- **Plain text (`.txt`)** — `TextFileExtractor` reads UTF-8 / falls back to ISO-8859-1, normalizes line endings.
- **Rich Text (`.rtf` / `.rtfd`)** — `RTFExtractor` uses `NSAttributedString(data:options:documentAttributes:)` with `.rtf` document type, returns plain text body.

### Deliberately deferred
- **MOBI / AZW / AZW3** — Kindle proprietary format. Would require either a third-party parser or running EPUB conversion server-side. Out of scope for v1.
- **HTML / web articles** — Useful but invites scope creep (reader-mode extraction, paywalls, JS-rendered pages). Defer to a future "Save Article" feature.
- **DOCX** — Possible via `NSAttributedString` document type, low demand for long-form reading. Can be added in 30 min when asked.

### Import flow
- Tap "+" in Library → system file picker (`.fileImporter`) with `[.pdf, .epub, .plainText, .rtf]`.
- AirDrop / Share Sheet → not yet wired (open question).
- iCloud Drive / Files → handled for free by `.fileImporter`.

## 3 · Reader View

The reader is the long-form companion to RSVP — used to set context, find a starting place, re-read a passage, or read normally.

### Visual design language
- **Type:** serif body (`bodySerif`), display serif for chapter titles. Configurable size 14–28 pt.
- **Color:** parchment background, ink-black text. Theme-aware: light parchment ↔ sepia ↔ night.
- **Layout:** generous horizontal padding (1.4× line-height vertical rhythm); max content width 680 pt on iPad.
- **Chrome:** translucent top bar with title/author + progress fraction; bottom bar with font controls, theme toggle, RSVP launch.

### Features (this iteration)
- ✅ Full extracted text rendered as a vertical scroll of paragraphs.
- ✅ Every word is a tap target; tapping a word seeds `lastReadWordIndex` and opens RSVP at that word.
- ✅ The "current" word (= `lastReadWordIndex` from RSVP) is rendered in crimson red, bold.
- ✅ On appear, the view auto-scrolls so the red word is centered.
- ✅ Font size +/- with stepped controls, persisted per device.
- ✅ Read progress indicator in the top bar (% complete).
- ✅ Bookmarks and highlights accessible from the toolbar.

### Features (deferred)
- Pagination mode (page-flip vs. continuous scroll). For now, continuous scroll only.
- Per-chapter table of contents. EPUB extractor already gathers chapter boundaries — surface them in a future iteration.
- Search within book. Defer.
- Inline definitions / dictionary lookup. Defer (system tap-and-hold dictionary works on selected text).

## 4 · Tap-to-RSVP & Red-Word Highlight

This is the connecting tissue between the two views.

### Behavior
1. **Reader view shows tappable words.** Each word in `book.words` (the same tokenization used by RSVP) is rendered as a tap target.
2. **Current word indicator.** `book.lastReadWordIndex` is highlighted in crimson red, bold weight.
3. **Tap a word.**
   - Set `book.lastReadWordIndex = tappedIndex`
   - Save context
   - Present `RSVPView(book:)` as full-screen cover
4. **RSVP loads from that index.** Already wired via `engine.load(words:startingAt: book.lastReadWordIndex)`.
5. **Dismiss RSVP.** Existing dismiss handler writes `book.lastReadWordIndex = engine.currentIndex`.
6. **Reader re-renders.** The new last-read word is shown in red; an explicit `.onChange(of: book.lastReadWordIndex)` triggers `ScrollViewReader.scrollTo(index, anchor: .center)`.

### Index identity
- `Book.words` re-tokenizes on every access. The reader caches the array as `@State` to avoid recomputation per render.
- The same tokenizer is used by both views, so an index is meaningful across them.

### Edge cases
- Empty book → fall back to the existing extractedText display, no taps.
- `lastReadWordIndex` out of bounds (book reimported with fewer words) → clamped to `0...words.count - 1`.
- Word duplicated in the text (e.g., "the" appears 50×) — index, not text, is the identity, so no ambiguity.

## 5 · Architecture

```
SpeedRead/
├── Extraction/
│   ├── TextExtractor.swift             # protocol
│   ├── PDFExtractor.swift               # existing
│   ├── EPUBExtractor.swift              # existing
│   ├── TextFileExtractor.swift          # NEW — .txt
│   └── RTFExtractor.swift               # NEW — .rtf
├── Services/
│   └── DocumentImporter.swift           # extended switch
├── Views/
│   ├── LibraryView.swift                # extended fileImporter content types
│   ├── ReaderView.swift                 # REWRITE — word-tap + red highlight
│   ├── ReaderWordFlow.swift             # NEW — wrapping flow layout for tappable words
│   ├── RSVPView.swift                   # unchanged behavior, already persists lastReadWordIndex
│   └── RSVPWordView.swift               # unchanged
└── Models/
    └── Book.swift                        # unchanged
```

## 6 · Testing strategy

- **Extractors** — `TextFileExtractorTests`, `RTFExtractorTests` round-trip sample data, verify Unicode + entity handling.
- **Reader word mapping** — already covered by `BookTests` (tokenization). Add tests for the `WordFlow` model: index ↔ word identity is preserved across paragraphs.
- **Tap-to-RSVP** — UI test that taps a word in the reader, asserts RSVP appears, dismisses, asserts the red highlight is on the last-shown word.
- **Manual verification** — XcodeBuildMCP simulator screenshots at each step (import a `.txt`, open reader, tap word, RSVP, dismiss, see red word).

## 7 · Open questions / followups

- [ ] Should we persist font size per-book or globally? (Currently global via `@AppStorage`.)
- [ ] Should reading position be by character offset rather than word index? Word index makes RSVP integration clean; consider only if scrubbing inside the reader becomes a feature.
- [ ] Add Share Sheet receiver so users can long-press a PDF in Safari → "Open in SpeedRead." Low effort, high value.
- [ ] When a book has hundreds of thousands of words, rendering every word as a Button has a measurable cost. Current solution: LazyVStack of paragraphs + custom flow layout per paragraph (only visible paragraphs realize their words). Revisit if perf is an issue on older devices.

## 8 · Changelog

- **2026-04-28** — Doc created. Implemented: TXT/RTF extractors, ReaderView rewrite with tap-to-RSVP and red-highlight, scroll-to-last-word. Tests added for extractors.
