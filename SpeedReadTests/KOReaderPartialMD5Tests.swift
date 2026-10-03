import Foundation
import Testing
@testable import SpeedRead

/// The digest is a sync server's key for a book, so it is only correct if it is bit-identical to
/// KOReader's. Every expected value here came from outside this repo: the synthetic vectors were
/// produced by a sync server's production implementation of the algorithm, and the bundled-book
/// digests by running that same implementation over our own sample files. None was computed by
/// the code under test.
@Suite("KOReader partial MD5")
struct KOReaderPartialMD5Tests {
    @Test func offsetsFollowLuaJITShiftSemantics() {
        // i = -1 shifts 1024 by (−2 & 31) = 30, which overflows 32 bits to 0.
        #expect(KOReaderPartialMD5.offsets == [
            0, 1_024, 4_096, 16_384, 65_536, 262_144, 1_048_576, 4_194_304,
            16_777_216, 67_108_864, 268_435_456, 1_073_741_824,
        ])
    }

    @Test("reference vectors", arguments: [
        (0, 1, "d41d8cd98f00b204e9800998ecf8427e"),
        // Only the first sample: the read at 1024 is empty.
        (1_000, 256, "cbecbdb0fdd5cec1e242493b6008cc79"),
        // Samples at 0, 1K and a 904-byte short read at 4K, which must still be hashed.
        (5_000, 7, "9243bab1092e42b23119c31de4f016eb"),
    ])
    func referenceVectors(length: Int, modulus: Int, expected: String) {
        let data = Data((0..<length).map { UInt8($0 % modulus) })
        #expect(KOReaderPartialMD5.digest(of: data) == expected)
    }

    @Test func samplesEveryOffsetUpToOneMebibyte() {
        let data = Data((0..<2_097_152).map { UInt8(($0 * 31 + 7) % 251) })
        #expect(KOReaderPartialMD5.digest(of: data) == "951d6ad62a386c5d5e49f4c898e5c6c2")
    }

    @Test("bundled sample books", arguments: [
        ("TheMetamorphosis", "cd4aad201fc3bba1606d427e4bd9a8e8"),
        ("TheYellowWallpaper", "6e9f9159336b7adabed2263ce5711ab0"),
    ])
    func bundledSampleBooks(name: String, expected: String) throws {
        let url = try #require(Bundle.main.url(forResource: name, withExtension: "epub"))
        #expect(KOReaderPartialMD5.digest(of: try Data(contentsOf: url)) == expected)
    }

    @Test func aSliceIsHashedFromItsOwnStart() {
        // Data slices keep their parent's indices; sampling must be relative to startIndex.
        let whole = Data((0..<6_000).map { UInt8($0 % 7) })
        let slice = whole[1_000..<6_000]
        #expect(KOReaderPartialMD5.digest(of: slice) == KOReaderPartialMD5.digest(of: Data(slice)))
    }
}
