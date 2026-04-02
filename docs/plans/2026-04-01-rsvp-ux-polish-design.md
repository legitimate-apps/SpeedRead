# RSVP View UX Polish Design

**Date:** 2026-04-01
**Status:** Approved
**Scope:** RSVPView.swift only

## Problem

The RSVP view has functional controls (close button, gear/settings, WPM display) but they are effectively unusable:

1. **Tap gesture conflict**: `Color.black.onTapGesture` on the ZStack background intercepts taps meant for the overlay buttons (X, gear icon).
2. **Poor discoverability**: White icons on black with no background chrome are easy to miss. Small tap targets.

## Solution: Approach B — Bug Fix + UX Polish

### 1. Fix Tap Gesture Conflict

- Remove `onTapGesture` from `Color.black` background.
- Add a transparent overlay between the top bar and bottom controls that handles the play/pause tap gesture.
- This ensures buttons in the top bar and bottom area receive taps correctly.

### 2. Top Bar UX Polish

- Add translucent capsule backgrounds (`ultraThinMaterial`) behind the close and gear buttons.
- Increase tap targets to minimum 44x44pt (Apple HIG).
- Add "Close" text label next to the X icon for discoverability.
- Make the WPM display tappable — opens the settings sheet as a shortcut.

### 3. No Other Changes

- ReaderView navigation unchanged (standard NavigationStack back chevron).
- Settings sheet (WPM slider, Done button) unchanged.
- No changes to RSVPEngine, models, or other views.

## Files Modified

- `SpeedRead/Views/RSVPView.swift`
