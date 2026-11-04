import SwiftData

extension ModelContainer {
    /// Keeps this container alive until the test process exits. Every container whose models
    /// reach a hosted view needs it.
    ///
    /// A hosted view outlives the test that hosted it. Hiding the window doesn't stop SwiftUI: a
    /// `.task` body already queued still runs after its cancellation, and `.onDisappear` fires
    /// whenever the window actually goes away. Either can read a `Book` after the test's locals
    /// are gone, and a SwiftData model traps on any attribute read once its container has been
    /// released ("This model instance was destroyed by calling ModelContext.reset"). The trap
    /// takes the whole test host down, and the test blamed is whichever one is running by then,
    /// not the one that left the work behind.
    ///
    /// Whether that queued work runs before or after the release depends on the machine's speed,
    /// so a suite can pass for months and then crash on a slower host. That is what happened on
    /// the MBP on 2026-11-03: the reader's scroll task from one test ran during the next test.
    /// The app holds its one container for the life of the process, so only tests can get here.
    @MainActor func keptAliveForHostedViews() -> ModelContainer {
        keptAliveContainers.append(self)
        return self
    }
}

@MainActor private var keptAliveContainers: [ModelContainer] = []
