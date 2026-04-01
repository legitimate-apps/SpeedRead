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
                .onTapGesture {
                    engine.togglePlayPause()
                }

            VStack {
                HStack {
                    Button {
                        book.lastReadWordIndex = engine.currentIndex
                        engine.stop()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    Text("\(engine.wpm) WPM")
                        .font(.caption)
                        .foregroundStyle(.gray)
                        .monospacedDigit()

                    Spacer()

                    Button {
                        showSettings.toggle()
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }
                }
                .padding()

                Spacer()

                RSVPWordView(segments: engine.currentSegments, fontSize: 36)

                Spacer()

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
