# Warm palette restyle — light & dark, warm & literary

**Status:** in flight. **Branch:** `style/warm-palette`. **Owner decisions pre-made** (see task brief):
retire coral `crimsonSoft` as accent; red survives ONLY as the reading `pivot` (RSVP ORP letter, guide
ticks, reader last-read word); chrome follows the OS appearance; reader page themes and shelf themes
keep their identity but stay legible in both appearances; contrast floor 4.5:1 text / 3:1 non-text.

## Evidence base

`ui-audit-before/AUDIT.md` (scratchpad, 60 screenshots, ranked findings). Its 12 top issues map to
tasks below. Where the audit suggested values, they were verified by WCAG math before adoption.

## Design decisions

1. **One semantic token set, adaptive light/dark**, defined in `SpeedRead/Theme/Theme.swift`
   (symlinked into the watch). Values resolved per appearance via a `Color.adaptive(light:dark:)`
   helper (`UIColor` dynamic provider on iOS; the dark value on watchOS, which is always dark).

   | Token | Light | Dark | Use |
   |---|---|---|---|
   | `appSurface` | parchment `#FFF8E7` | `#1A1210` | sheet/chrome backgrounds |
   | `appSurfaceRaised` | parchmentDark `#F0E6D0` | `#251A14` | list rows, cards |
   | `appInk` | inkBlack `#1C1410` | `#F5EDE0` | primary text |
   | `appInkSecondary` | walnutLight `#5D4037` | `#B9A98F` | secondary text |
   | `accent` | saddle `#7A4A2B` | gold `#D9B968` | buttons, links, tint |
   | `onAccent` | parchment `#FFF8E7` | `#1A1210` | text on accent fills |
   | `goldText` | `#8A6A1F` | `#D9B968` | readable gold text |
   | `pivot` | `#B3261E` | `#E2574C` | ORP letter, guide ticks, last-read word ONLY |
   | `error` | `#A23B2A` | `#E8806F` | validation/destructive text |

   Verified pairs (WCAG): saddle/parchment 6.98, gold/`#1A1210` 9.75, pivotL/parchment 6.17,
   pivotL/sepia 5.52, pivotD/`#1A1210` 5.01, errorL 6.21, errorD 6.81, walnutLight 8.80, goldTextL 4.77.
   `agedGold #C8A951` and `lamplight` remain ornament/fill colors only, never text on light surfaces.

2. **Error is a distinct brick, not pivot red.** "Red = your place in the text" stays crisp because
   errors never appear on reading surfaces. This replaces `crimsonSoft` double-duty (accent AND error).

3. **AccentColor asset catalogs** (iOS + watch) get saddle-light/gold-dark so system blue leaks die
   (sliders, toggles, URL fields, review stars). `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME` is
   already `AccentColor`, so this is global without code.

4. **Sheets are app chrome**: they stop keying off the *shelf* theme and use the adaptive tokens
   (light OS = parchment sheet, dark OS = warm `#1A1210` sheet). Rows get explicit
   `.listRowBackground(appSurfaceRaised)`; nav bars get `.toolbarColorScheme` per surface lightness.
   Serif nav titles via one `UINavigationBar` appearance configuration.

5. **Shelf themes keep character**; each gains `isDark` so the library nav bar takes a matching
   `toolbarColorScheme` (Classic/Vintage/Modern → light chrome even in dark OS; Midnight → dark chrome
   even in light OS). Classic spine palette biases warm (drop teal/slate/navy for oxblood/forest/ochre);
   Midnight's plank lifts from 1.06:1 invisible to a warm `#4A3426` with a lamplight highlight.

6. **Reader palettes stay independent of OS**; per-palette `accent` (parchment/sepia: saddle fill +
   parchment text RSVP pill; night: gold fill + ink text) and per-palette `pivot`. Night warms from
   cool `#101012` to `#17110E` so night-reader and RSVP read as one family. Reader sub-sheets
   (chapters/bookmarks/highlights/settings) render on the palette, not system grey.

7. **RSVP** (always dark): play button gold fill + ink glyph; pivot token for ORP/ticks; WPM steppers,
   progress track and word counts lifted above 4.5:1.

8. **Radii**: 6 (chips/covers), 12 (cards/banners), Capsule (buttons). Type: serif display for
   titles, serif body for prose, system sans for controls, mono for numbers.

9. **New pure logic lives alone with tests**: `SpeedRead/Theme/ContrastRatio.swift` (WCAG math) +
   `SpeedReadTests/ContrastRatioTests.swift` asserting every shipped token pair clears the floor.
   Nothing view-adjacent. Attributable-coverage floor untouched.

## Constraints carried from the brief

- `Theme.swift` is symlinked into the watch target; shared files stay single (`shared-source-audit.py`).
- No `@AppStorage` key renames; no changes under `SpeedRead/Sync/`.
- Behaviour unchanged; UI-test accessibility labels/identifiers preserved ("Next", "Open Your Library",
  "Reader menu", "Chapters", "Close chapters", "Start RSVP from current word", "watch-position-offer*",
  "rsvp-current-chapter", word labels in WordFlowLayout; `Button` + `.buttonStyle(.plain)` there).
- Watch: lighter touch — accent/palette swap + `WatchPositionOfferBanner` legibility; keep it building.

## Commit order (small, by path)

1. `SpeedRead/Theme/` + `SpeedReadTests/` — adaptive tokens, `pivot`, contrast helper + tests.
2. Asset catalogs — AccentColor light/dark, both targets.
3. `SpeedRead/SpeedReadApp.swift` — serif nav-title appearance.
4. `SpeedRead/Views/` library group — LibraryView, BookshelfRowView, BookSpineView, ShelfTheme,
   SpineColor, LibraryLayoutMetrics fill-to-viewport, ThemePickerView.
5. `SpeedRead/Views/SettingsView.swift` + `SpeedRead/Views/Server/` — chrome + dark-mode blockers.
6. `SpeedRead/Views/OnboardingView.swift` — dark variant, saddle/gold CTAs, page dots.
7. Reader group — ReaderTheme, ReaderView, ReaderSheets, EmptyStateView.
8. RSVP group — RSVPView, RSVPWordView, RSVPPlaybackControl, Bookmark/HighlightListView.
9. Watch — view accent swaps (AccentColor asset does the rest).

## Verification

- `Scripts/honesty-gates.sh`; hermetic iOS suite on sim 6D8221D0; watch scheme builds.
- Screenshots light+dark for every screen the audit covered, into `ui-after/` (scratchpad), JPEG 600px.
- Contrast test suite guards the token table above against regressions.
