//  RemoteBookDetailView.swift
import SwiftUI
import SwiftData

struct RemoteBookDetailView: View {
    let server: OPDSServer
    let entry: OPDSEntry
    let onAdded: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeManager.self) private var themeManager

    @State private var selectedAcquisitionIndex: Int = 0
    @State private var downloading = false
    @State private var downloadError: String?
    @State private var coverImage: Image?

    private var supportedAcquisitions: [OPDSAcquisition] {
        entry.acquisitions.filter {
            switch $0.mimeType {
            case "application/epub+zip",
                 "application/pdf",
                 "text/plain",
                 "application/rtf",
                 "text/rtf": return true
            default: return false
            }
        }
    }

    private var selectedAcquisition: OPDSAcquisition? {
        guard selectedAcquisitionIndex < supportedAcquisitions.count else {
            return supportedAcquisitions.first
        }
        return supportedAcquisitions[selectedAcquisitionIndex]
    }

    var body: some View {
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
                        Picker("Format", selection: $selectedAcquisitionIndex) {
                            ForEach(Array(supportedAcquisitions.enumerated()), id: \.offset) { idx, acq in
                                Text(acq.displayFormat).tag(idx)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    downloadButton
                    if let downloadError {
                        Text(downloadError)
                            .font(.footnote)
                            .foregroundStyle(Color.crimsonSoft)
                    }
                    if supportedAcquisitions.isEmpty {
                        Text("No supported formats. SpeedRead can read EPUB, PDF, TXT, and RTF.")
                            .font(.footnote)
                            .foregroundStyle(Color.walnutLight)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadCover() }
    }

    @ViewBuilder
    private var cover: some View {
        if let coverImage {
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

    private var downloadButton: some View {
        Button {
            Task { await performDownload() }
        } label: {
            HStack {
                if downloading {
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
        .disabled(downloading || selectedAcquisition == nil)
    }

    private func loadCover() async {
        guard let url = entry.coverURL ?? entry.thumbnailURL else { return }
        if let cached = OPDSCoverCache.shared.image(for: url) {
            coverImage = cached
            return
        }
        let client = OPDSClient()
        do {
            let payload = try await client.download(from: url, on: server)
            #if canImport(UIKit)
            if let ui = UIImage(data: payload.data) {
                let image = Image(uiImage: ui)
                OPDSCoverCache.shared.store(image, for: url)
                coverImage = image
            }
            #endif
        } catch {
            // Cover failures are non-fatal — caller stays on the placeholder.
        }
    }

    private func performDownload() async {
        guard let acquisition = selectedAcquisition else { return }
        downloading = true
        downloadError = nil
        let client = OPDSClient()
        do {
            let payload = try await client.download(from: acquisition.url, on: server)
            let filename = ensureExtension(payload.filename, mimeType: acquisition.mimeType)
            let importer = DocumentImporter(modelContext: modelContext)
            let book = try importer.importData(payload.data, filename: filename)
            onAdded(book.title)
            dismiss()
        } catch let err as OPDSError {
            downloadError = err.errorDescription
        } catch let err as ExtractionError {
            downloadError = "Couldn't extract text from the downloaded file (\(err))."
        } catch {
            downloadError = error.localizedDescription
        }
        downloading = false
    }

    /// CWNG sometimes serves files without a proper extension on the filename
    /// (e.g. trailing-slash URLs). The importer routes on extension, so we
    /// patch one in from the mime type when needed.
    private func ensureExtension(_ filename: String, mimeType: String) -> String {
        let nsName = filename as NSString
        let ext = nsName.pathExtension.lowercased()
        if !ext.isEmpty {
            return filename
        }
        let mimeExt: String
        switch mimeType {
        case "application/epub+zip": mimeExt = "epub"
        case "application/pdf": mimeExt = "pdf"
        case "application/rtf", "text/rtf": mimeExt = "rtf"
        case "text/plain": mimeExt = "txt"
        default: mimeExt = "bin"
        }
        let base = filename.isEmpty ? entry.title.replacingOccurrences(of: "/", with: "_") : filename
        return "\(base).\(mimeExt)"
    }
}
