# RSVP View UX Polish Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix broken button taps and improve control discoverability in RSVPView.

**Architecture:** Single-file change to RSVPView.swift. Move tap gesture off background, add material-backed button chrome, enlarge tap targets, add Close label, make WPM tappable.

**Tech Stack:** SwiftUI, iOS 17+

---

### Task 1: Fix Tap Gesture Conflict

**Files:**
- Modify: `SpeedRead/Views/RSVPView.swift:11-17` (ZStack background area)

**Step 1: Remove onTapGesture from Color.black**

Replace the current ZStack opening (lines 12-17):

```swift
ZStack {
    Color.black
        .ignoresSafeArea()
        .onTapGesture {
            engine.togglePlayPause()
        }
```

With:

```swift
ZStack {
    Color.black
        .ignoresSafeArea()
```

**Step 2: Add transparent tap overlay between top bar and bottom controls**

After the `RSVPWordView` line (line 52), wrap the Spacers and word view in a tap-receiving overlay. Replace lines 50-54:

```swift
                Spacer()

                RSVPWordView(segments: engine.currentSegments, fontSize: 36)

                Spacer()
```

With:

```swift
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        engine.togglePlayPause()
                    }

                RSVPWordView(segments: engine.currentSegments, fontSize: 36)

                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        engine.togglePlayPause()
                    }
```

**Step 3: Build and verify**

Run: `xcodebuild build -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 16' -quiet`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add SpeedRead/Views/RSVPView.swift
git commit -m "fix: remove background tap gesture that blocked RSVP control buttons"
```

---

### Task 2: Polish Top Bar — Close Button with Label and Material Background

**Files:**
- Modify: `SpeedRead/Views/RSVPView.swift:20-29` (close button in HStack)

**Step 1: Replace the close button**

Replace lines 21-29:

```swift
                    Button {
                        book.lastReadWordIndex = engine.currentIndex
                        engine.stop()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
```

With:

```swift
                    Button {
                        book.lastReadWordIndex = engine.currentIndex
                        engine.stop()
                        dismiss()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark")
                            Text("Close")
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                    .frame(minWidth: 44, minHeight: 44)
```

**Step 2: Build and verify**

Run: `xcodebuild build -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 16' -quiet`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add SpeedRead/Views/RSVPView.swift
git commit -m "feat: add Close label and material capsule to RSVP dismiss button"
```

---

### Task 3: Polish Top Bar — Gear Button with Material Background

**Files:**
- Modify: `SpeedRead/Views/RSVPView.swift:40-46` (gear button)

**Step 1: Replace the gear button**

Replace lines 40-46:

```swift
                    Button {
                        showSettings.toggle()
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
```

With:

```swift
                    Button {
                        showSettings.toggle()
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .frame(minWidth: 44, minHeight: 44)
```

**Step 2: Build and verify**

Run: `xcodebuild build -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 16' -quiet`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add SpeedRead/Views/RSVPView.swift
git commit -m "feat: add material circle background to RSVP settings button"
```

---

### Task 4: Make WPM Display Tappable

**Files:**
- Modify: `SpeedRead/Views/RSVPView.swift:33-36` (WPM text)

**Step 1: Wrap WPM text in a tappable button**

Replace lines 33-36:

```swift
                    Text("\(engine.wpm) WPM")
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .monospacedDigit()
```

With:

```swift
                    Button {
                        showSettings.toggle()
                    } label: {
                        Text("\(engine.wpm) WPM")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .monospacedDigit()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .frame(minHeight: 44)
```

**Step 2: Build and verify**

Run: `xcodebuild build -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 16' -quiet`
Expected: BUILD SUCCEEDED

**Step 3: Commit**

```bash
git add SpeedRead/Views/RSVPView.swift
git commit -m "feat: make WPM display tappable to open speed settings"
```

---

### Task 5: Run Full Test Suite

**Step 1: Run all tests**

Run: `xcodebuild test -scheme SpeedRead -destination 'platform=iOS Simulator,name=iPhone 16' -quiet`
Expected: All 63 tests pass, no regressions

**Step 2: Final commit if any adjustments needed**
