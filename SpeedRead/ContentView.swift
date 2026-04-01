//  ContentView.swift
import SwiftUI
import SwiftData

struct ContentView: View {
    var body: some View {
        LibraryView()
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Book.self, inMemory: true)
}
