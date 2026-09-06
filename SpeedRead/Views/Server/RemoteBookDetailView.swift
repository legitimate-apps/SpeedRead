//  RemoteBookDetailView.swift
import SwiftUI
import SwiftData

struct RemoteBookDetailView: View {
    let server: OPDSServer
    let entry: OPDSEntry
    let onAdded: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.opdsClientFactory) private var makeClient
    @Environment(ThemeManager.self) private var themeManager

    @State private var session: RemoteBookDetailSession

    init(server: OPDSServer, entry: OPDSEntry, onAdded: @escaping (String) -> Void, session: RemoteBookDetailSession? = nil) {
        self.server = server
        self.entry = entry
        self.onAdded = onAdded
        _session = State(initialValue: session ?? RemoteBookDetailSession())
    }

    var body: some View {
        let availability = OPDSFormatAvailabilityLogic.classify(entry.acquisitions)
        let supportedAcquisitions = availability.readable
        ZStack {
            themeManager.currentTheme.backgroundColor.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    cover
                        .frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.title)
                            .font(.displayFont(size: 26, weight: .regular))
                            .foregroundStyle(Color.walnut)
                        if !entry.authors.isEmpty {
                            Text(entry.authors.joined(separator: ", "))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.walnutLight)
                        }
                        if let language = entry.language, !language.isEmpty {
                            Text("Language: \(language.uppercased())")
                                .font(.caption)
                                .foregroundStyle(Color.walnutLight)
                        }
                    }
                    if let summary = entry.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.body)
                            .foregroundStyle(Color.walnut)
                    }
                    if supportedAcquisitions.count > 1 {
                        Picker("Format", selection: $session.selectedAcquisitionIndex) {
                            ForEach(Array(supportedAcquisitions.enumerated()), id: \.offset) { idx, acq in
                                Text(acq.displayFormat).tag(idx)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    downloadButton
                    if let downloadError = session.downloadError {
                        Text(downloadError)
                            .font(.footnote)
                            .foregroundStyle(Color.crimsonSoft)
                    }
                    if !availability.unreadableDisplayNames.isEmpty {
                        unavailableFormats(availability.unreadableDisplayNames)
                    } else if supportedAcquisitions.isEmpty {
                        Text("This book has no downloadable formats.")
                            .font(.footnote)
                            .foregroundStyle(Color.walnutLight)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task { await session.loadCover(entry: entry, on: server, makeClient: makeClient) }
    }

    @ViewBuilder
    private var cover: some View {
        if let coverImage = session.coverImage {
            coverImage
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 280)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(radius: 4)
        } else if entry.coverURL != nil || entry.thumbnailURL != nil {
            ProgressView()
                .controlSize(.large)
                .frame(height: 280)
        } else {
            Image(systemName: "book.closed")
                .font(.system(size: 100))
                .foregroundStyle(Color.walnutLight)
                .frame(height: 280)
        }
    }

    @ViewBuilder
    private func unavailableFormats(_ displayNames: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(displayNames, id: \.self) { name in
                    Text(name)
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.walnutLight.opacity(0.15), in: Capsule())
                        .foregroundStyle(Color.walnutLight)
                }
            }
            Text(OPDSFormatAvailabilityLogic.unavailableFormatMessage)
                .font(.footnote)
                .foregroundStyle(Color.walnutLight)
            Link(
                OPDSFormatAvailabilityLogic.supportRequestLabel,
                destination: OPDSFormatAvailabilityLogic.supportRequestURL
            )
            .font(.footnote.weight(.medium))
            .foregroundStyle(Color.crimsonSoft)
        }
    }

    private var downloadButton: some View {
        let supportedAcquisitions = RemoteBookDetailLogic.supportedAcquisitions(
            from: entry.acquisitions
        )
        let selectedAcquisition = RemoteBookDetailLogic.resolvedAcquisition(
            at: session.selectedAcquisitionIndex,
            in: supportedAcquisitions
        )
        return Button {
            Task { await session.performDownload(entry: entry, on: server, modelContext: modelContext, makeClient: makeClient, onAdded: onAdded, dismiss: { dismiss() }) }
        } label: {
            HStack {
                if session.downloading {
                    ProgressView().controlSize(.small).tint(Color.parchment)
                    Text("Downloading…")
                } else {
                    Image(systemName: "arrow.down.circle.fill")
                    Text("Download & Add to Library")
                }
            }
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Color.parchment)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(Color.crimsonSoft, in: Capsule())
        }
        .disabled(session.downloading || selectedAcquisition == nil)
    }

}
