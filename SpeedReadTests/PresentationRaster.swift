import SwiftUI
import Testing

/// Shared by symlink with the watch test target. Samples retain position, not just a color set.
@MainActor
struct PresentationRaster: Equatable, CustomStringConvertible {
    var description: String { "Raster(\(width)x\(height))" }
    let width: Int
    let height: Int
    let pixels: [UInt32]

    init<V: View>(_ view: V, width: CGFloat? = nil, height: CGFloat? = nil) throws {
        let renderer = ImageRenderer(content: view)
        renderer.proposedSize = ProposedViewSize(width: width, height: height)
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        self.width = image.width
        self.height = image.height
        let data = try #require(image.dataProvider?.data)
        let bytes = try #require(CFDataGetBytePtr(data))
        let step = image.bitsPerPixel / 8
        #expect(step == 4)
        pixels = (0..<image.height).flatMap { y in
            (0..<image.width).map { x in
                let offset = y * image.bytesPerRow + x * step
                return UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16
                    | UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3])
            }
        }
    }

    func region(x: Range<Int>, y: Range<Int>) -> [UInt32] {
        y.flatMap { row in x.map { pixels[row * width + $0] } }
    }
}
