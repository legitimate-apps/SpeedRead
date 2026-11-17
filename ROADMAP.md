# SpeedRead roadmap

What's planned, in rough order. The detailed backlog, with every bug and idea and its history, is
[docs/plans/2026-04-28-audit-and-roadmap.md](docs/plans/2026-04-28-audit-and-roadmap.md); the IDs
below (B, I, F) refer to it.

## Now: 1.4 to the App Store

1.4 adds chapters, server position and annotation sync, the live phone↔watch handoff, the new RSVP
scrub, long-token handling and the iOS 27 PDF fix. Next in line behind it, already on TestFlight:

- **Calibre-Web-NextGen client round**: each device names itself to the server so going back to an
  earlier place syncs, server errors read as sentences, series, covers kept on disk at the size they
  are shown, and streamed downloads.
- **"Share my place" note**: when a server can take your position but the setting is off, the
  library and the reader say so once, with a way to turn it on.

## Next

- **iPhone ↔ iPad sync** (F10). Phone and watch share one place, and a library server can carry a
  place between any readers, but two Apple devices without a server still don't. The plan is
  SwiftData with CloudKit, so the data stays in the user's own iCloud.
- **Search within a book** (F1): find a phrase, jump to it, read on from there in either mode.
- **Watch on real hardware.** The watch flows are covered by tests and paired-simulator runs; a
  recorded end-to-end pass on a physical watch is still owed.
- **Accessibility**: Dynamic Type throughout (I17), a higher-contrast night-theme highlight (I18),
  per-paragraph VoiceOver grouping with words as custom actions (I16), and skip-by-sentence in RSVP
  (I19).
- **Large books**: tokenize off the main actor (I1) and virtualize word ranges, not only paragraphs
  (I21).
- **A guide to connecting your own library server**: finding the address, plain HTTP on a home
  network, and signing in.

## Later

- Reader polish: long-press a word for define, copy, highlight or bookmark (I7); edit a book's title
  and author (I12); reset reading settings (I11).
- RSVP options: 2–3 word chunks at high speeds (F5), a punctuation-pause control (F4), a tunable focus
  letter (F17), and pause at chapter ends (F15).
- Reading stats, goals and streaks (F3, F18).
- Export highlights and notes as Markdown or to other apps (F9).
- Import articles from Safari's share sheet (F8) and drag-and-drop on iPad (F20).
- Collections and tags (F21).
- An OpenDyslexic font option (F13).
- Languages without spaces between words, such as Chinese and Japanese, which need their own
  tokenizer (F28).

## Engineering

- Unify the reader theme and shelf theme into one system (I28).
- Replace the two separate bookmark and highlight list implementations with one (B16).
- Keep the honesty gates and the 90% attributable-coverage floor as the bar for every change.
