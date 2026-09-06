import SwiftUI
import Testing

/// Inspects actual renderer pixels, shared by both platform test targets.
@MainActor
enum RSVPRenderProbe {
    struct Ink {
        let left: Int
        let right: Int
        let focusCenter: Double
    }

    static func wordInk(in image: CGImage) throws -> Ink {
        let context = try #require(CGContext(
            data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        var columns: [Int] = []
        var redColumns: [Int] = []
        // Exclude the 8pt guide marks and the 2pt gaps at the top and bottom.
        for y in 10..<(image.height - 10) {
            for x in 0..<image.width {
                let offset = (y * image.width + x) * 4
                guard pixels[offset + 3] > 20 else { continue }
                columns.append(x)
                if Int(pixels[offset]) > Int(pixels[offset + 1]) * 2 {
                    redColumns.append(x)
                }
            }
        }
        let left = try #require(columns.min())
        let right = try #require(columns.max())
        let focusLeft = try #require(redColumns.min())
        let focusRight = try #require(redColumns.max())
        return Ink(left: left, right: right, focusCenter: Double(focusLeft + focusRight + 1) / 2)
    }
}
