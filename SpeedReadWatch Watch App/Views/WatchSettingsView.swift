import SwiftUI

struct WatchSettingsView: View {
    var engine: RSVPEngine
    let chapters: [ChapterMark]
    let currentWordIndex: Int
    let onSelectChapter: (ChapterMark) -> Void
    let onRestoreReadingPosition: () -> Void
    @Environment(\.dismiss) private var dismiss

    var chapterList: WatchChapterListView? {
        guard !chapters.isEmpty else { return nil }
        return WatchChapterListView(chapters: chapters, currentWordIndex: currentWordIndex,
                                    onSelect: onSelectChapter)
    }

    func restoreReadingPosition() { onRestoreReadingPosition() }

    var body: some View {
        NavigationStack {
            List { rows }
            .navigationTitle("Reading Settings")
            .accessibilityIdentifier("watch-reading-settings-list")
        }
    }

    @ViewBuilder
    var rows: some View {
        if let chapterList {
            NavigationLink {
                chapterList
            } label: {
                Label(
                    WatchSettingsLogic.title(for: .chapter),
                    systemImage: "list.bullet.rectangle"
                )
            }
            .accessibilityIdentifier("watch-chapter-settings-row")
        }

        Button {
            restoreReadingPosition()
            dismiss()
        } label: {
            Label(
                WatchSettingsLogic.title(for: .backToReadingPosition),
                systemImage: "arrow.uturn.backward"
            )
        }

        NavigationLink {
            WatchSpeedSettingsView(engine: engine)
        } label: {
            LabeledContent(
                WatchSettingsLogic.title(for: .speed),
                value: WatchSettingsLogic.speedValue(wpm: engine.wpm)
            )
        }
    }
}

struct WatchChapterListView: View {
    let chapters: [ChapterMark]
    let currentWordIndex: Int
    let onSelect: (ChapterMark) -> Void

    var currentChapter: ChapterMark? {
        WatchSettingsLogic.currentChapter(in: chapters, at: currentWordIndex)
    }

    func select(_ chapter: ChapterMark) { onSelect(chapter) }

    func chapterLabel(_ chapter: ChapterMark) -> some View {
        HStack {
            Text(chapter.title)
            Spacer()
            if chapter == currentChapter {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.agedGold)
            }
        }
    }

    var body: some View {
        List(chapters, id: \.self) { chapter in
            Button { select(chapter) } label: { chapterLabel(chapter) }
                .accessibilityIdentifier("watch-chapter-\(chapter.startWordIndex)")
        }
        .navigationTitle("Chapters")
        .accessibilityIdentifier("watch-chapter-list")
    }
}

struct WatchSpeedSettingsView: View {
    var engine: RSVPEngine
    @State private var wpmValue: Double = 300

    var body: some View {
        WatchSpeedSettingsControl(engine: engine, wpmValue: $wpmValue)
    }
}

/// The crown and Done button share this binding and commit path. The owning view keeps
/// the draft local; an explicit defaults store allows isolated previews and tests.
struct WatchSpeedSettingsControl: View {
    var engine: RSVPEngine
    @Binding var wpmValue: Double
    @Environment(\.dismiss) private var dismiss
    @AppStorage private var persistedWPM: Int

    init(engine: RSVPEngine, wpmValue: Binding<Double>, defaults: UserDefaults = .standard) {
        self.engine = engine
        _wpmValue = wpmValue
        _persistedWPM = AppStorage(wrappedValue: 300, "rsvpLastWPM", store: defaults)
    }

    var crownValue: Binding<Double> {
        Binding(get: { wpmValue }, set: { wpmValue = Double(WatchSettingsLogic.snappedWPM($0)) })
    }

    func loadSpeed() {
        crownValue.wrappedValue = Double(engine.wpm)
    }

    func saveSpeed() {
        persistedWPM = WatchSettingsLogic.apply(wpmValue, to: engine)
    }

    var controls: some View {
        VStack(spacing: 12) {
            Text("\(Int(wpmValue))")
                .font(.numeric(size: 36))
                .foregroundStyle(Color.agedGold)

            Text("Words Per Minute")
                .font(.system(size: 11))
                .foregroundStyle(Color.parchment.opacity(0.6))

            Button("Done") {
                saveSpeed()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.crimsonSoft)
        }
    }

    var body: some View {
        controls
        .containerBackground(Color.walnut.gradient, for: .navigation)
        .focusable()
        .digitalCrownRotation(
            crownValue,
            from: Double(WatchSettingsLogic.wpmRange.lowerBound),
            through: Double(WatchSettingsLogic.wpmRange.upperBound),
            by: WatchSettingsLogic.wpmStep,
            sensitivity: .low,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onAppear(perform: loadSpeed)
    }
}
