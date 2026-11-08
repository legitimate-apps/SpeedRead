//  OPDSCoverCache.swift
import Foundation
import SwiftUI
import UIKit

/// Cover cache keyed by URL: a bounded memory cache over a bounded directory of downscaled copies.
/// The copies are SpeedRead's own, so a server's `Cache-Control: no-store` (CWNG sends it on
/// covers) does not make every launch fetch every cover again. Bytes are pulled by the regular
/// OPDSClient, which already knows how to authenticate against each server.
@MainActor
final class OPDSCoverCache {
    static let shared = OPDSCoverCache(
        directory: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OPDSCovers", isDirectory: true)
    )

    let directory: URL?
    private var images: [URL: Image] = [:]
    private var insertionOrder: [URL] = []
    private let softCap: Int
    private let diskCap: Int

    init(softCap: Int = 200, directory: URL? = nil, diskCap: Int = 1_000) {
        precondition(softCap >= 0, "Cover cache capacity cannot be negative")
        self.softCap = softCap
        self.directory = directory
        self.diskCap = diskCap
    }

    func image(for url: URL) -> Image? {
        if let image = images[url] { return image }
        guard let file = file(for: url), let data = try? Data(contentsOf: file), let ui = UIImage(data: data) else {
            return nil
        }
        let image = Image(uiImage: ui)
        store(image, for: url)
        return image
    }

    func store(_ image: Image, for url: URL) {
        if images[url] == nil {
            insertionOrder.append(url)
        }
        images[url] = image
        while insertionOrder.count > softCap {
            let oldest = insertionOrder.removeFirst()
            images.removeValue(forKey: oldest)
        }
    }

    /// Keeps a downloaded cover, downscaled, and returns it; nil when the bytes are no image.
    func store(data: Data, for url: URL) -> Image? {
        guard let kept = OPDSCoverLogic.downscaled(data), let ui = UIImage(data: kept) else { return nil }
        let image = Image(uiImage: ui)
        store(image, for: url)
        if let directory, let file = file(for: url) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if (try? kept.write(to: file, options: .atomic)) != nil { trimDisk(in: directory) }
        }
        return image
    }

    private func file(for url: URL) -> URL? {
        directory?.appendingPathComponent(OPDSCoverLogic.fileName(for: url))
    }

    /// Oldest written first out, so the directory stays a bounded cache.
    private func trimDisk(in directory: URL) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]),
              files.count > diskCap else { return }
        let dated = files.map { ($0, (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }
        for (file, _) in dated.sorted(by: { $0.1 < $1.1 }).prefix(files.count - diskCap) {
            try? fm.removeItem(at: file)
        }
    }
}
