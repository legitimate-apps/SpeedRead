//  RSVPView.swift
import SwiftUI

struct RSVPView: View {
    @Bindable var book: Book
    @Environment(\.dismiss) private var dismiss

    @State private var engine = RSVPEngine()
    @State private var showSettings = false

    var body: some View {
        ZStack {
            // Warm dark background with vignette
            Color.rsvpBackground
                .ignoresSafeArea()
                .overlay(
                    RadialGradient(
                        colors: [.clear, .black.opacity(0.3)],
                        center: .center,
                        startRadius: 200,
                        endRadius: 500
                    )
                    .ignoresSafeArea()
                )

            VStack {
                // Header
                HStack {
                    Button {
                        book.lastReadWordIndex = engine.currentIndex
                        engine.stop()
                        dismiss()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark")
                            Text("Close")
                        }
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.rsvpText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.walnut.opacity(0.6), in: Capsule())
                    }
                    .frame(minWidth: 44, minHeight: 44)

                    Spacer()

                    Button {
                        showSettings.toggle()
                    } label: {
                        Text("\(engine.wpm) WPM")
                            .font(.numeric(size: 14, weight: .medium))
                            .foregroundStyle(Color.agedGold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.walnut.opacity(0.6), in: Capsule())
                    }
                    .frame(minHeight: 44)
                    .accessibilityLabel("\(engine.wpm) words per minute, tap to adjust")

                    Spacer()

                    Button {
                        showSettings.toggle()
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Color.rsvpText)
                            .padding(10)
                            .background(Color.walnut.opacity(0.6), in: Circle())
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Settings")
                }
                .padding()

                // Word display area
                VStack(spacing: 0) {
                    Color.clear
                    RSVPWordView(segments: engine.currentSegments, fontSize: 36)
                    Color.clear
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    engine.togglePlayPause()
                }

                // Bottom controls
                VStack(spacing: 16) {
                    if engine.state != .playing {
                        Button {
                            engine.play()
                        } label: {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 64))
                                .foregroundStyle(Color.crimsonSoft)
                        }
                        .transition(.opacity.animation(.easeInOut(duration: 0.15)))
                    }

                    VStack(spacing: 4) {
                        // Gold progress bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.walnut)
                                    .frame(height: 4)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.agedGold.opacity(0.7), Color.agedGold],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: geo.size.width * engine.progress, height: 4)
                                    .animation(.linear(duration: 0.1), value: engine.progress)
                            }
                        }
                        .frame(height: 4)

                        HStack {
                            Text("Word \(engine.currentIndex + 1)")
                            Spacer()
                            Text("of \(engine.totalWords)")
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(Color.rsvpText.opacity(0.4))
                        .monospacedDigit()
                    }
                    .padding(.horizontal)
                }
                .padding(.bottom, 40)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            engine.load(words: book.words, startingAt: book.lastReadWordIndex)
        }
        .onDisappear {
            book.lastReadWordIndex = engine.currentIndex
        }
        .sheet(isPresented: $showSettings) {
            wpmSettingsSheet
        }
    }

    private var wpmSettingsSheet: some View {
        NavigationStack {
            ZStack {
                Color.rsvpBackground.ignoresSafeArea()

                VStack(spacing: 24) {
                    Text("\(engine.wpm)")
                        .font(.numeric(size: 64))
                        .foregroundStyle(Color.agedGold)

                    Text("Words Per Minute")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.rsvpText.opacity(0.5))

                    Slider(
                        value: Binding(
                            get: { Double(engine.wpm) },
                            set: { engine.wpm = Int($0) }
                        ),
                        in: 100...1000,
                        step: 25
                    )
                    .tint(Color.agedGold)
                    .padding(.horizontal)

                    HStack {
                        Text("100")
                        Spacer()
                        Text("1000")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Color.rsvpText.opacity(0.4))
                    .padding(.horizontal)

                    Spacer()
                }
                .padding(.top, 40)
            }
            .navigationTitle("Speed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showSettings = false
                    }
                    .foregroundStyle(Color.agedGold)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
