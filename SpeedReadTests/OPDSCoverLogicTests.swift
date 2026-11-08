import Foundation
import ImageIO
import Testing
import UIKit
@testable import SpeedRead

@Suite("OPDS cover logic")
struct OPDSCoverLogicTests {
    @Test func aLargeCoverIsKeptAtTheSizeItIsShown() throws {
        let kept = try #require(OPDSCoverLogic.downscaled(Self.png(width: 1_200, height: 1_800)))
        #expect(Self.pixelSize(kept) == CGSize(width: 560, height: 840))
        #expect(kept.count < Self.png(width: 1_200, height: 1_800).count)
    }

    @Test func aSmallCoverIsNotEnlarged() throws {
        let kept = try #require(OPDSCoverLogic.downscaled(Self.png(width: 40, height: 60)))
        #expect(Self.pixelSize(kept) == CGSize(width: 40, height: 60))
    }

    @Test func bytesThatAreNoImageAreNoCover() {
        #expect(OPDSCoverLogic.downscaled(Data("<html>not a cover</html>".utf8)) == nil)
        #expect(OPDSCoverLogic.downscaled(Data()) == nil)
    }

    @Test func eachURLHasItsOwnFile() throws {
        let small = try #require(URL(string: "https://covers.example/book.jpg?size=small"))
        let large = try #require(URL(string: "https://covers.example/book.jpg?size=large"))
        #expect(OPDSCoverLogic.fileName(for: small) != OPDSCoverLogic.fileName(for: large))
        #expect(OPDSCoverLogic.fileName(for: small) == OPDSCoverLogic.fileName(for: small))
        #expect(OPDSCoverLogic.fileName(for: small).hasSuffix(".jpg"))
    }

    static func png(width: Int, height: Int) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image {
            UIColor.systemTeal.setFill()
            $0.fill(CGRect(x: 0, y: 0, width: width, height: height))
            UIColor.white.setFill()
            $0.fill(CGRect(x: width / 4, y: height / 4, width: width / 2, height: height / 8))
        }.pngData()!
    }

    static func pixelSize(_ data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return CGSize(width: width, height: height)
    }
}
