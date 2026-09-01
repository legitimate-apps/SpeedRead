//  WatchBookDetailView.swift
import SwiftUI
#if os(watchOS)
import WatchKit
#endif

struct WatchBookDetailView: View {
    let book: WatchBook
    @EnvironmentObject var syncService: WatchSyncService
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false

    private var spineColor: Color {
        SpineColor.color(for: book.title)
    }

    private var latestBook: WatchBook {
        WatchBookDetailPresentation.latestBook(for: book, in: syncService.library)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text(latestBook.title)
                    .font(.displayFont(size: 18, weight: .semibold))
                    .foregroundStyle(Color.parchment)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)

                Text(latestBook.author)
                    .font(.displayFont(size: 13, weight: .regular))
                    .foregroundStyle(Color.parchment.opacity(0.7))
                    .multilineTextAlignment(.center)

                Rectangle()
                    .fill(Color.agedGold.opacity(0.3))
                    .frame(height: 1)
                    .padding(.horizontal)

                HStack {
                    VStack(spacing: 2) {
                        Text("\(WatchBookDetailPresentation.progressPercentage(for: latestBook))%")
                            .font(.numeric(size: 18))
                            .foregroundStyle(Color.agedGold)
                        Text("Progress")
                            .font(.caption)
                            .foregroundStyle(Color.parchment.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)

                    VStack(spacing: 2) {
                        Text(latestBook.wordCount.formatted())
                            .font(.numeric(size: 18))
                            .foregroundStyle(Color.parchment)
                        Text("Words")
                            .font(.caption)
                            .foregroundStyle(Color.parchment.opacity(0.6))
                    }
                    .frame(maxWidth: .infinity)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.parchment.opacity(0.15))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.agedGold)
                            .frame(width: geo.size.width * latestBook.progress)
                    }
                }
                .frame(height: 4)
                .padding(.horizontal)

                Button {
                    WatchBookDetailLogic.select(book, in: &syncService.library)
                    syncService.persistLibrary()
                    WKInterfaceDevice.current().play(.success)
                    dismiss()
                } label: {
                    Text(WatchBookDetailLogic.readingActionTitle(lastReadIndex: latestBook.lastReadIndex))
                        .font(.system(size: 15, weight: .semibold, design: .serif))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.crimsonSoft)

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Text("Remove from Watch")
                        .font(.caption)
                        .foregroundStyle(Color.crimsonSoft.opacity(0.7))
                }
                .buttonStyle(.plain)
                .confirmationDialog("Remove this book?", isPresented: $showDeleteConfirmation) {
                    Button("Remove", role: .destructive) {
                        WatchBookDetailLogic.remove(book, from: &syncService.library)
                        syncService.persistLibrary()
                        dismiss()
                    }
                }
            }
            .padding(.top, 8)
        }
        .containerBackground(spineColor.gradient, for: .navigation)
    }
}
