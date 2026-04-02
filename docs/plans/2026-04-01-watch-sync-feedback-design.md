# Watch Sync Feedback Design

**Date:** 2026-04-01
**Status:** Approved
**Scope:** WatchSyncService, LibraryView, NowReadingView

## Problem

Book syncing from iPhone to Watch has zero feedback on both sides:
1. iPhone: tapping "Send to Watch" gives no confirmation or error
2. Watch: no indication a book is arriving
3. Received book data is lost on Watch app restart (not persisted)

## Solution: Approach B — Rich Feedback + Persistence

### 1. iPhone — Send Feedback

- Check `WCSession.default.isReachable` before sending; show "Watch not connected" alert if not
- Replace silent `try?` with proper error handling in `sendBook()`
- Show toast overlay in LibraryView: "Sending [title] to Watch..." during transfer
- On transfer completion, update to "Sent to Watch" with checkmark
- On failure, show "Failed to send" error toast
- Toast auto-dismisses after 2 seconds

### 2. Watch — Receive Feedback

- Track incoming file transfers via WCSession delegate
- Show "Receiving [title]..." card with ProgressView spinner in NowReadingView
- Use transfer metadata (title/author) to show what's arriving before file completes
- Animate transition from receiving card to normal book card
- Haptic tap (`.notification(.success)`) when book arrives

### 3. Watch — Persistence

- Save received book data (title, author, text, reading position) to JSON file in Watch documents directory
- Load persisted data on app launch in WatchSyncService
- Overwrite when new book received
- Book survives app restart without re-sending

### 4. No Other Changes

- Keep manual "Send to Watch" context menu
- Keep existing reading position sync via applicationContext
- No changes to RSVP engine or reading flow

## Files Modified

- `SpeedRead/Connectivity/WatchSyncService.swift` — error handling, transfer tracking, persistence
- `SpeedRead/Views/LibraryView.swift` — toast overlay, reachability check
- `SpeedReadWatch Watch App/Views/NowReadingView.swift` — receiving card, animation
- `SpeedReadWatch Watch App/SpeedReadWatchApp.swift` — load persisted data on launch
