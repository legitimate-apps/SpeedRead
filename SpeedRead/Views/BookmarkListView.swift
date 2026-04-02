//  BookmarkListView.swift
import SwiftUI

struct BookmarkListView: View {
    @Bindable var book: Book
    let engine: RSVPEngine

    var body: some View {
        Text("Bookmarks")
    }
}
