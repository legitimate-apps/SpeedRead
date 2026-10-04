//  OPDSEntryRowView.swift
import SwiftUI

struct OPDSEntryRowView: View {
    let entry: OPDSEntry
    let coverProvider: (URL) async -> Image?

    @State private var coverImage: Image?

    var body: some View {
        let acquisitionLabels = OPDSAcquisitionLabelLogic.labels(for: entry.acquisitions)
        HStack(alignment: .top, spacing: 12) {
            cover
                .frame(width: 56, height: 84)
                .background(Color.appInkSecondary.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.appInk.opacity(0.15), lineWidth: 0.5)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.appInk)
                    .lineLimit(2)
                if !entry.authors.isEmpty {
                    Text(entry.authors.joined(separator: ", "))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.appInkSecondary)
                        .lineLimit(1)
                }
                ForEach(OPDSMetadataLogic.discoveryFields(for: entry)) { field in
                    Text(field.text)
                        .font(.caption)
                        .foregroundStyle(Color.appInkSecondary)
                        .lineLimit(2)
                }
                if !entry.acquisitions.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(entry.acquisitions.enumerated()), id: \.offset) { index, acq in
                            let tint = OPDSFormatAvailabilityLogic.isReadable(acq)
                                ? Color.appGoldText
                                : Color.appInkSecondary
                            Text(acquisitionLabels[index])
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(tint.opacity(0.15), in: Capsule())
                                .foregroundStyle(tint)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .task {
            guard let url = entry.thumbnailURL ?? entry.coverURL else { return }
            coverImage = await coverProvider(url)
        }
    }

    @ViewBuilder
    private var cover: some View {
        if let coverImage {
            coverImage
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else if entry.thumbnailURL != nil || entry.coverURL != nil {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Image(systemName: "book.closed")
                .font(.system(size: 24))
                .foregroundStyle(Color.appInkSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
