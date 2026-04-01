//  SpeedReadApp.swift
import SwiftUI
import SwiftData

@main
struct SpeedReadApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: Book.self)
    }
}
