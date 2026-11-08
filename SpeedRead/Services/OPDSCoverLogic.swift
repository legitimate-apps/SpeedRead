import Foundation
import ImageIO
import UniformTypeIdentifiers
import CryptoKit

/// Covers are kept at the size they are shown, not the size a server sends.
nonisolated enum OPDSCoverLogic {
    /// The detail page shows a cover 280 points tall, at up to 3x; the browse row's 84 points
    /// fits inside that, so one copy serves both.
    static let maxPixelSize = 840

    /// A JPEG no larger than `maxPixelSize` on its longest side; nil when the bytes are no image.
    static func downscaled(_ data: Data, maxPixelSize: Int = maxPixelSize) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0 else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// Where a cover's copy is kept: a digest of its whole URL, query included.
    static func fileName(for url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined() + ".jpg"
    }
}
