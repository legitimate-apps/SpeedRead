//  ReaderView.swift
import SwiftUI

struct ReaderView: View {
    @Bindable var book: Book
    @State private var fontSize: CGFloat = 18
    @State private var showRSVP = false

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                Text(book.extractedText)
                    .font(.system(size: fontSize))
                    .padding()
                    .padding(.bottom, 80)
                    .textSelection(.enabled)
            }

            HStack {
                HStack(spacing: 12) {
                    Button {
                        fontSize = max(12, fontSize - 2)
                    } label: {
                        Text("A-")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .buttonStyle(.bordered)

                    Button {
                        fontSize = min(32, fontSize + 2)
                    } label: {
                        Text("A+")
                            .font(.system(size: 18, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                Button {
                    showRSVP = true
                } label: {
                    Label("RSVP", systemImage: "bolt.fill")
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
            .padding()
            .background(.ultraThinMaterial)
        }
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showRSVP) {
            RSVPView(book: book)
        }
    }
}
