//  ReaderView.swift
import SwiftUI

struct ReaderView: View {
    @Bindable var book: Book
    @State private var fontSize: CGFloat = 18
    @State private var showRSVP = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.parchment.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(book.title)
                        .font(.displayFont(size: 24, weight: .bold))
                        .foregroundStyle(Color.inkBlack)

                    Text(book.author)
                        .font(.bodySerif(size: 16))
                        .foregroundStyle(Color.walnutLight)

                    Divider()
                        .background(Color.walnutLight.opacity(0.3))
                        .padding(.vertical, 8)

                    Text(book.extractedText)
                        .font(.bodySerif(size: fontSize))
                        .foregroundStyle(Color.inkBlack)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 100)
            }

            // Bottom toolbar
            HStack {
                HStack(spacing: 12) {
                    Button {
                        fontSize = max(12, fontSize - 2)
                    } label: {
                        Text("A\u{2212}")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.parchment)
                            .frame(width: 36, height: 36)
                            .background(Color.walnutLight, in: RoundedRectangle(cornerRadius: 8))
                    }

                    Button {
                        fontSize = min(28, fontSize + 2)
                    } label: {
                        Text("A+")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(Color.parchment)
                            .frame(width: 36, height: 36)
                            .background(Color.walnutLight, in: RoundedRectangle(cornerRadius: 8))
                    }
                }

                Spacer()

                Button {
                    showRSVP = true
                } label: {
                    Text("Start Reading")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.parchment)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.crimsonSoft, in: Capsule())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Color.walnut
                    .opacity(0.95)
                    .ignoresSafeArea(edges: .bottom)
            )
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.parchment, for: .navigationBar)
        .fullScreenCover(isPresented: $showRSVP) {
            RSVPView(book: book)
        }
    }
}
