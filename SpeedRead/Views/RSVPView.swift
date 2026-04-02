//  RSVPView.swift
import SwiftUI

struct RSVPView: View {
    @Bindable var book: Book
    @Environment(\.dismiss) private var dismiss

    @State private var engine = RSVPEngine()
    @State private var showSettings = false

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack {
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
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                    }
                    .frame(minWidth: 44, minHeight: 44)

                    Spacer()

                    Button {
                        showSettings.toggle()
                    } label: {
                        Text("\(engine.wpm) WPM")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .monospacedDigit()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .frame(minHeight: 44)
                    .accessibilityLabel("\(engine.wpm) words per minute, tap to adjust")

                    Spacer()

                    Button {
                        showSettings.toggle()
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityLabel("Settings")
                }
                .padding()

                VStack(spacing: 0) {
                    Color.clear
                    RSVPWordView(segments: engine.currentSegments, fontSize: 36)
                    Color.clear
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    engine.togglePlayPause()
                }

                VStack(spacing: 16) {
                    if engine.state != .playing {
                        Button {
                            engine.play()
                        } label: {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 64))
                                .foregroundStyle(.red)
                        }
                    }

                    VStack(spacing: 4) {
                        ProgressView(value: engine.progress)
                            .tint(.red)
                        HStack {
                            Text("Word \(engine.currentIndex + 1)")
                            Spacer()
                            Text("of \(engine.totalWords)")
                        }
                        .font(.caption2)
                        .foregroundStyle(.gray)
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
            VStack(spacing: 24) {
                Text("\(engine.wpm)")
                    .font(.system(size: 64, weight: .bold, design: .monospaced))
                    .foregroundStyle(.red)

                Text("Words Per Minute")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Slider(
                    value: Binding(
                        get: { Double(engine.wpm) },
                        set: { engine.wpm = Int($0) }
                    ),
                    in: 100...1000,
                    step: 25
                )
                .tint(.red)
                .padding(.horizontal)

                HStack {
                    Text("100")
                    Spacer()
                    Text("1000")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 40)
            .navigationTitle("Speed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        showSettings = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
