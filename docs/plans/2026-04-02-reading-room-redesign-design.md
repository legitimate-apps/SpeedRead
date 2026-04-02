# The Reading Room — SpeedRead UI/UX Redesign

**Date:** 2026-04-02
**Status:** Approved
**Scope:** Visual/UX layer redesign — no engine, extraction, or architecture changes

## Vision

Transform SpeedRead from a functional speed-reading tool into a **cozy library** experience. Warm, communal, abundant — books are just there for you. The design evokes reading in a dimly lit library corner with an old book: tactile, warm, and inviting.

**Target users:** Students and casual readers, reading for pleasure or interest.

---

## Color System

### Core Palette

| Token | Hex | Usage |
|-------|-----|-------|
| `walnut` | `#3E2723` | Shelf backgrounds, primary dark surface |
| `walnutLight` | `#5D4037` | Secondary surfaces, card backgrounds |
| `parchment` | `#FFF8E7` | Main background, text surfaces |
| `parchmentDark` | `#F0E6D0` | Alternate rows, subtle depth |
| `inkBlack` | `#1C1410` | Primary text |
| `crimson` | `#C62828` | ORP focus character (functional) |
| `crimsonSoft` | `#D4574A` | UI buttons, progress bars, accents |
| `agedGold` | `#C8A951` | Highlights, selected states, badges |
| `lamplight` | `#FFE0A0` | Subtle glow effects, warm accents |

### RSVP Mode Palette

| Token | Hex | Usage |
|-------|-----|-------|
| `rsvpBackground` | `#1A1210` | Warm near-black |
| `rsvpText` | `#F5EDE0` | Warm off-white |
| `rsvpCrimson` | `#C62828` | ORP focus — sharp for function |

### Dark Mode

Surfaces shift to walnut tones, text inverts to warm cream-on-dark. The library "after hours" feel.

### Implementation

All defined as a `Color` extension with semantic names, shared across iOS and watchOS.

---

## Typography

### Font Choices

| Role | Font | Weight | Usage |
|------|------|--------|-------|
| Display | New York (SF Serif Display) | Bold | App title, section headers, book titles on shelves |
| Body | New York (SF Serif) | Regular | Book text in reader, descriptions, onboarding copy |
| UI Controls | SF Pro | Medium/Semibold | Buttons, labels, navigation items |
| RSVP Word | SF Mono | Bold | Speed-reading word display (unchanged) |
| Numbers | SF Mono | Regular | WPM display, progress counts |

### Type Scale (iOS)

| Element | Spec |
|---------|------|
| Library title | New York, 34pt, Bold |
| Book title on spine | New York, 14pt, Semibold |
| Book author on spine | SF Pro, 11pt, Regular |
| Reader body text | New York, 16-28pt, Regular (adjustable) |
| RSVP main word | SF Mono, 36pt, Bold |
| WPM display | SF Mono, 48pt, Bold |
| Button labels | SF Pro, 15pt, Medium |

### Watch Scale

Proportionally smaller — New York 13pt for titles, SF Mono 20pt for RSVP word.

---

## Library Screen — The Bookshelf

### Layout

Vertical scroll of wooden shelf rows. Each shelf holds 3-4 books displayed as upright spines. Shelf has a warm walnut gradient appearance (pure SwiftUI, no image assets).

### Book Spines

Generated spines based on book title:

- Deterministic color from curated palette of 8-10 rich, muted colors (deep teal, burgundy, forest green, navy, burnt sienna, plum, slate blue, ochre)
- Color selected by hashing book title — consistent across sessions
- Title printed vertically along spine in New York serif, cream/gold text
- Subtle embossed effect via shadow
- Height varies slightly by word count — organic, lived-in look
- Reading progress shown as subtle gold line at bottom of spine

### Structure

```
┌─────────────────────────────────┐
│  "Your Library"    [+] import   │  New York Bold header
├─────────────────────────────────┤
│  ┌──┐ ┌──┐ ┌───┐ ┌──┐         │
│  │  │ │  │ │   │ │  │         │  Book spines, varying heights
│  │  │ │  │ │   │ │  │         │
│  ════════════════════════       │  Shelf plank (walnut gradient)
│  ┌──┐ ┌──┐                     │
│  │  │ │  │                     │  Second shelf row
│  ════════════════════════       │
└─────────────────────────────────┘
```

### Interactions

- Tap spine → book slides out, opens ReaderView (animated)
- Long press → context menu (Send to Watch, Delete)
- Import button → file picker (PDF/EPUB)

### Empty State

Empty wooden shelves with: *"Your shelves are waiting..."* in New York italic. Prominent, warm import button.

---

## Reader View

### Design

- **Background:** Parchment cream (`#FFF8E7`)
- **Text:** New York serif, adjustable 16-28pt, `inkBlack`
- **Margins:** Generous 24pt horizontal padding (book-like)
- **Top bar:** Book title (New York semibold), author (SF Pro light)
- **Position indicator:** Subtle gold bookmark ribbon on right edge

### Controls (bottom toolbar)

- Font size A-/A+ — warm, tactile buttons
- "Start Reading" button (replaces "RSVP") — crimsonSoft background, cream text, capsule
- Toolbar: walnut dark background with slight transparency

### Transition to RSVP

Parchment dims to warm dark RSVP background — smooth cross-fade like turning off the reading lamp.

---

## RSVP View

### Background

`rsvpBackground` (`#1A1210`) with subtle linen/paper grain texture overlay at 3-5% opacity. Generated with SwiftUI, not bitmap. Physicality without distraction.

### Word Display

- SF Mono Bold 36pt in `rsvpText` (warm off-white `#F5EDE0`)
- ORP focus character in `crimson` (`#C62828`) — unchanged, functional
- Guide marks shift to crimson to match
- Subtle warm vignette — edges slightly darker, center brighter (lamplight pooling)

### Controls (paused state)

- Close, Settings, Play — `rsvpText` with crimsonSoft accents
- Bottom bar: warm frosted glass, slightly tinted
- WPM display: SF Mono, `agedGold` — brass instrument readout feel

### Progress Bar

- Thin line along bottom
- Track: `walnut` dark
- Fill: `agedGold` gradient — warm light advancing across page

### Settings Sheet (WPM)

- Dark warm surface matching RSVP background
- WPM number in `agedGold`, large SF Mono
- Slider track walnut, thumb agedGold

### Motion

- Play/pause: word fades in/out (0.15s)
- Opening RSVP: cross-fade from parchment to dark (0.4s ease)
- Progress bar: smooth animated fill

---

## Watch App — Pocket Edition

### Now Reading View

- Background: deep walnut tone
- Book title: New York serif, cream text
- Play button: crimsonSoft filled circle, cream play icon
- No book state: *"Open your library on iPhone"* in New York italic

### Watch RSVP View

- Background: `rsvpBackground` (warm near-black) — matches iOS
- Word display: warm off-white + crimson ORP, 20pt
- Paused controls: cream icons, crimsonSoft accents
- WPM display: `agedGold` SF Mono

### Watch Settings

- Dark walnut surface
- WPM in agedGold
- Digital Crown adjustment

---

## Onboarding

### Flow (3 screens + library)

**Screen 1 — Welcome:**
- Parchment background
- *"Welcome to SpeedRead"* — New York Bold, large
- *"Your cozy reading library"*
- Open book icon with crimson speed lines
- "Next" button in crimsonSoft

**Screen 2 — How RSVP Works:**
- Brief animated demo showing word with red ORP focus character
- *"One word at a time, right where your eye naturally lands"*
- 3-second live demo cycling through words
- "Next" button

**Screen 3 — Get Started:**
- *"We've placed a few books on your shelf to get started"*
- Lists 2-3 sample titles (public domain classics)
- *"Import your own PDFs and EPUBs anytime"*
- "Open Your Library" button → LibraryView with books on shelves

**Implementation:** TabView with PageTabViewStyle, UserDefaults flag for first launch.

---

## What Changes vs. What Stays

### Changes (visual/UX layer)

| Area | Current | Redesigned |
|------|---------|------------|
| Color | System `.red`, black, white | Walnut/parchment/crimson/gold semantic palette |
| Typography | System fonts only | New York serif + SF Pro + SF Mono |
| Library | Plain List rows | Wooden shelf metaphor with generated book spines |
| Reader | Raw scrollable text | Parchment page with book margins and serif text |
| RSVP | Pure black, white text | Warm dark + linen texture, off-white text, gold progress |
| Watch | Minimal black UI | Warm walnut surfaces, matching typography |
| Onboarding | None | 3-screen welcome + pre-loaded sample books |
| Motion | Almost none | Gentle transitions, lamp-dimming RSVP entry |
| Empty state | Generic icon + text | Warm shelves with inviting message |

### Unchanged

- RSVP engine, ORP calculation, word timing
- PDF/EPUB extraction logic
- Watch connectivity and sync (WatchSyncService)
- Core architecture (SwiftData, @Observable, NavigationStack)
- Data model (Book)
- Test suite
