import CryptoKit
import Foundation

/// KOReader's document identifier: MD5 over 1 KiB samples taken at 0, 1K, 4K, 16K, ... 1G,
/// stopping at the first offset past the end. A sample cut short by EOF is still hashed.
///
/// Sync servers key reading progress on this digest (KOSync `document`), and a server that
/// served the file registers the same digest for the bytes it sent — so it must be computed
/// over the downloaded bytes exactly, before anything rewrites them.
/// Reference: KOReader `frontend/util.lua` `partialMD5`; the offsets come from LuaJIT's
/// `bit.lshift(1024, 2*i)` for i in -1...10, where the shift count is masked to 5 bits, so
/// i = -1 shifts by 30 and overflows 32 bits to offset 0.
nonisolated enum KOReaderPartialMD5 {
    static let sampleSize = 1024
    static let offsets: [Int] = (-1...10).map { i in
        Int(truncatingIfNeeded: UInt32(truncatingIfNeeded: 1024 << ((2 * i) & 0x1F)))
    }

    static func digest(of data: Data) -> String {
        var md5 = Insecure.MD5()
        for offset in offsets {
            guard offset < data.count else { break }
            let end = min(offset + sampleSize, data.count)
            md5.update(data: data[data.startIndex + offset ..< data.startIndex + end])
        }
        return md5.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
