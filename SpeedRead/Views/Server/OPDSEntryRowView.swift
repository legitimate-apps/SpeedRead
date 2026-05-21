//  OPDSEntryRowView.swift
import SwiftUI

struct OPDSEntryRowView: View {
    let entry: OPDSEntry
    let coverProvider: (URL) async -> Image?

    @State private var coverImage: Image?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            cover
                .frame(width: 56, height: 84)
                .background(Color.walnutLight.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.walnut.opacity(0.2), lineWidth: 0.5)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.walnut)
                    .lineLimit(2)
                if !entry.authors.isEmpty {
                    Text(entry.authors.joined(separator: ", "))
                        .font(.system(size: 12))
                        .foregroundStyle(Color.walnutLight)
                        .lineLimit(1)
                }
                if !entry.acquisitions.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(Array(entry.acquisitions.enumerated()), id: \.offset) { _, acq in
                            Text(acq.displayFormat)
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.crimsonSoft.opacity(0.15), in: Capsule())
                                .foregroundStyle(Color.crimsonSoft)
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
                .foregroundStyle(Color.walnutLight)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
