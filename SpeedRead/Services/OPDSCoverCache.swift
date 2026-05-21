//  OPDSCoverCache.swift
import Foundation
import SwiftUI

/// Memory-only cover cache keyed by URL. Bounded to a soft cap so big
/// catalogs don't blow up RAM. Backing image bytes are pulled by the
/// regular OPDSClient (which already knows how to authenticate against
/// each server).
@MainActor
final class OPDSCoverCache {
    static let shared = OPDSCoverCache()

    private var images: [URL: Image] = [:]
    private var insertionOrder: [URL] = []
    private let softCap: Int = 200

    func image(for url: URL) -> Image? {
        images[url]
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
}
