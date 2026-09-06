import SwiftUI
import SwiftData
import Testing
import UIKit
@testable import SpeedRead

@Suite("Launch and settings surfaces", .serialized)
@MainActor
struct LaunchSurfaceTests {
    @Test func onboardingPagesHaveDistinctContentAndCompletionPersists() async throws {
        let storage = IsolatedDefaults()
        let view = OnboardingView(hasCompletedOnboarding: Binding(
            get: { storage.defaults.bool(forKey: "hasCompletedOnboarding") },
            set: { storage.defaults.set($0, forKey: "hasCompletedOnboarding") }))
        // Render each page directly. TabView's UIKit child containers are tested by XCUITest.
        func render<Page: View>(_ page: Page) async throws -> RenderSignature {
            let host = UIHostingController(rootView: page.background(Color.parchment))
            let window = try hostWindow(host)
            defer { window.isHidden = true; window.rootViewController = nil }
            return try await signature(host.view)
        }
        let welcome = try await render(view.welcomePage)
        let explanation = try await render(view.rsvpExplanationPage)
        let ready = try await render(view.getStartedPage)
        #expect(welcome != explanation, "Welcome and explanation must show different content")
        #expect(explanation != ready, "Explanation and ready pages must show different content")
        #expect(welcome != ready, "Welcome and ready pages must show different content")
        #expect(!storage.defaults.bool(forKey: "hasCompletedOnboarding"))
        try buttonAction(in: view.getStartedPage)()
        #expect(storage.defaults.bool(forKey: "hasCompletedOnboarding"), "Open Your Library must persist completion through its binding")
    }

    @Test func contentGateTracksCompletionInBothDirectionsAndClaimsReviewOnce() async throws {
        let storage = IsolatedDefaults()
        storage.defaults.set(2, forKey: "reviewPromptLaunchCount")
        let gate = ReviewPromptProcessGate()
        var requests = 0
        let connection = FakeWatchConnectivitySession()
        let service = WatchSyncService(session: connection)
        let container = try memoryContainer()
        let theme = ThemeManager(defaults: storage.defaults)
        func root() -> some View {
            ContentView(defaults: storage.defaults, reviewPromptGate: gate,
                        reviewRequest: { requests += 1 })
                .modelContainer(container).environment(theme).environmentObject(service)
        }
        let host = UIHostingController(rootView: root())
        let window = try hostWindow(host)
        defer { window.isHidden = true; window.rootViewController = nil }
        let onboarding = try await signature(host.view)
        #expect(subviews(host.view, as: UIPageControl.self).count == 1)
        #expect(connection.activationCount == 1, "ContentView task must activate the injected sync service")
        #expect(requests == 1, "The third launch must request review from the view's onAppear")
        #expect(storage.defaults.integer(forKey: "reviewPromptLaunchCount") == 3)

        storage.defaults.set(true, forKey: "hasCompletedOnboarding")
        let library = try await signature(host.view)
        #expect(subviews(host.view, as: UIPageControl.self).isEmpty, "Completion must replace onboarding with the library")
        #expect(library != onboarding)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Book>()) == 4)
        storage.defaults.set(false, forKey: "hasCompletedOnboarding")
        _ = try await signature(host.view)
        #expect(subviews(host.view, as: UIPageControl.self).count == 1, "Clearing completion must restore onboarding")

        // A new root identity/window produces another real onAppear in the same process.
        window.isHidden = true
        window.rootViewController = nil
        let secondHost = UIHostingController(rootView: root())
        let secondWindow = try hostWindow(secondHost)
        defer { secondWindow.isHidden = true; secondWindow.rootViewController = nil }
        _ = try await signature(secondHost.view)
        #expect(requests == 1, "Recreating ContentView must not request a second review")
        #expect(storage.defaults.integer(forKey: "reviewPromptLaunchCount") == 3, "One process must count only one launch")
        #expect(subviews(secondHost.view, as: UIPageControl.self).count == 1)
    }

    @Test func contentDoesNotRequestReviewBeforeThirdLaunch() async throws {
        let storage = IsolatedDefaults()
        storage.defaults.set(1, forKey: "reviewPromptLaunchCount")
        var requests = 0
        let host = UIHostingController(rootView:
            ContentView(defaults: storage.defaults, reviewPromptGate: ReviewPromptProcessGate(),
                        reviewRequest: { requests += 1 })
                .modelContainer(try memoryContainer())
                .environment(ThemeManager(defaults: storage.defaults))
                .environmentObject(WatchSyncService(session: FakeWatchConnectivitySession())))
        let window = try hostWindow(host)
        defer { window.isHidden = true; window.rootViewController = nil }
        _ = try await signature(host.view)
        #expect(storage.defaults.integer(forKey: "reviewPromptLaunchCount") == 2)
        #expect(requests == 0)
        #expect(subviews(host.view, as: UIPageControl.self).count == 1)
    }

    @Test func themeButtonsPersistSelectionAndUpdatePicker() async throws {
        let storage = IsolatedDefaults()
        let manager = ThemeManager(defaults: storage.defaults)
        let picker = ThemePickerView()
        let host = UIHostingController(rootView: picker.environment(manager))
        let window = try hostWindow(host)
        defer { window.isHidden = true; window.rootViewController = nil }
        let classicPicker = try await signature(host.view)
        var previousPicker = classicPicker
        for theme in [ShelfTheme.midnight, .modern, .vintage, .classic] {
            try buttonAction(in: picker.themeCard(theme, manager: manager))()
            let selectedPicker = try await signature(host.view)
            #expect(manager.currentTheme.id == theme.id, "The theme button must update ThemeManager")
            #expect(storage.defaults.string(forKey: "selectedThemeId") == theme.id, "Selection must persist in the injected store")
            #expect(ThemeManager(defaults: storage.defaults).currentTheme.id == theme.id)
            #expect(selectedPicker != previousPicker, "Selection must update the picker appearance")
            previousPicker = selectedPicker
        }
        #expect(previousPicker == classicPicker, "Reselecting Classic must restore its appearance")
    }

    @Test func settingsDisplaysEachSelectedTheme() async throws {
        let storage = IsolatedDefaults()
        let manager = ThemeManager(defaults: storage.defaults)
        let host = UIHostingController(rootView: SettingsView().environment(manager)
            .modelContainer(try memoryContainer()))
        let window = try hostWindow(host)
        defer { window.isHidden = true; window.rootViewController = nil }
        let classic = try await signature(host.view)
        var previous = classic
        for theme in [ShelfTheme.midnight, .modern, .vintage, .classic] {
            manager.selectedThemeId = theme.id
            let selected = try await signature(host.view)
            #expect(manager.currentTheme.id == theme.id)
            #expect(selected != previous, "Settings must display the selected theme")
            previous = selected
        }
        #expect(previous == classic, "Reselecting Classic must restore the Settings background")
    }

    @Test func appSchemaContainsEveryPersistedModel() throws {
        let schema = Schema(SpeedReadApp.modelTypes)
        let names = Set(schema.entities.map(\.name))
        #expect(names == ["Book", "Bookmark", "Highlight", "OPDSServer"], "The shipping scene schema must contain all four models")
        // Stop before inserting a missing model: the schema assertion is the regression, not a crash.
        guard names == ["Book", "Bookmark", "Highlight", "OPDSServer"] else { return }
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let book = Book(title: "Schema", author: "Reader", extractedText: "one two", sourceFileName: "schema.txt")
        book.bookmarks = [Bookmark(wordIndex: 0, previewText: "one")]
        book.highlights = [Highlight(startWordIndex: 0, endWordIndex: 1, highlightedText: "one two")]
        context.insert(book)
        context.insert(OPDSServer(name: "Local", baseURL: URL(string: "https://example.invalid/opds")!, username: ""))
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<Book>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Bookmark>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Highlight>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<OPDSServer>()) == 1)
    }

    private func memoryContainer() throws -> ModelContainer {
        try ModelContainer(for: Book.self, Bookmark.self, Highlight.self, OPDSServer.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    // White-box invocation of the real Button action. UIKit/gesture dispatch is not asserted here.
    // The iOS 26.5 SwiftUI closure's actor metadata does not dynamically cast to the SDK's
    // MainActor function type, although the macOS version does. Restrict the ABI bridge to
    // this exact zero-argument Void closure representation, and fail on any SDK shape change.
    private func buttonAction(in value: Any) throws -> @MainActor () -> Void {
        func actions(_ value: Any, depth: Int) -> [Any] {
            guard depth < 20 else { return [] }
            if String(reflecting: type(of: value)) == "@Swift.MainActor () -> ()" { return [value] }
            let mirror = Mirror(reflecting: value)
            guard mirror.displayStyle != .class else { return [] }
            return mirror.children.flatMap { actions($0.value, depth: depth + 1) }
        }
        let found = actions(value, depth: 0)
        #expect(found.count == 1, "Expected exactly one Button action in this view fragment")
        let erased = try #require(found.first)
        func open<T>(_ value: T) throws -> @MainActor () -> Void {
            try #require(MemoryLayout<T>.size == MemoryLayout<@MainActor () -> Void>.size)
            return unsafeBitCast(value, to: (@MainActor () -> Void).self)
        }
        return try _openExistential(erased, do: open)
    }

    private func subviews<T: UIView>(_ view: UIView, as type: T.Type) -> [T] {
        (view as? T).map { [$0] } ?? [] + view.subviews.flatMap { subviews($0, as: type) }
    }

    private func hostWindow<V: View>(_ host: UIHostingController<V>) throws -> UIWindow {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        return window
    }

    private struct RenderSignature: Equatable, CustomTestStringConvertible {
        let samples: [UInt32]
        var testDescription: String { "Rendered image (\(samples.count) spatial RGB samples)" }
    }

    private func signature(_ view: UIView) async throws -> RenderSignature {
        try await Task.sleep(for: .milliseconds(500))
        view.setNeedsLayout()
        view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(bounds: view.bounds, format: format).image {
            view.layer.render(in: $0.cgContext)
        }
        let cg = try #require(image.cgImage)
        let data = try #require(cg.dataProvider?.data)
        let bytes = try #require(CFDataGetBytePtr(data))
        #expect(cg.bitsPerPixel == 32)
        var samples: [UInt32] = []
        for y in stride(from: 110, to: cg.height - 40, by: 3) {
            for x in stride(from: 12, to: cg.width - 12, by: 3) {
                let offset = y * cg.bytesPerRow + x * 4
                samples.append(UInt32(bytes[offset]) << 16 | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]))
            }
        }
        #expect(Set(samples).count > 8, "A blank render is not evidence")
        return RenderSignature(samples: samples)
    }
}
