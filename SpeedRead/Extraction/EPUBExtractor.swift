//  EPUBExtractor.swift
import Foundation
import Compression

struct EPUBExtractor: TextExtractor {

    func extractText(from data: Data) throws -> ExtractionResult {
        let entries: [String: Data]
        do {
            entries = try Self.unzipEntries(from: data)
        } catch {
            throw ExtractionError.invalidData
        }

        guard let containerData = entries["META-INF/container.xml"],
              let containerXML = String(data: containerData, encoding: .utf8) else {
            throw ExtractionError.parsingFailed("Missing META-INF/container.xml")
        }

        guard let opfPath = parseContainerForOPFPath(containerXML) else {
            throw ExtractionError.parsingFailed("Could not find OPF path in container.xml")
        }

        guard let opfData = entries[opfPath],
              let opfXML = String(data: opfData, encoding: .utf8) else {
            throw ExtractionError.parsingFailed("Could not read OPF file at \(opfPath)")
        }

        let opfDir: String
        if let lastSlash = opfPath.lastIndex(of: "/") {
            opfDir = String(opfPath[opfPath.startIndex...lastSlash])
        } else {
            opfDir = ""
        }

        let metadata = parseOPFMetadata(opfXML)
        let spineHrefs = parseOPFSpineHrefs(opfXML)

        var chapters: [String] = []
        for href in spineHrefs {
            let decoded = href.removingPercentEncoding ?? href
            let fullPath = opfDir + decoded
            if let fileData = entries[fullPath],
               let xhtml = String(data: fileData, encoding: .utf8) {
                let text = Self.stripHTML(xhtml)
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    chapters.append(text)
                }
            }
        }

        let fullText = chapters.joined(separator: "\n\n")

        return ExtractionResult(
            text: fullText,
            title: metadata.title,
            author: metadata.author
        )
    }

    // MARK: - Minimal ZIP Reader

    /// Reads all entries from a ZIP archive into memory.
    /// Supports Store (method 0) and Deflate (method 8).
    static func unzipEntries(from data: Data) throws -> [String: Data] {
        var entries: [String: Data] = [:]
        var offset = 0
        let bytes = [UInt8](data)
        let count = bytes.count

        while offset + 30 <= count {
            // Local file header signature = 0x04034b50
            let sig = readUInt32(bytes, at: offset)
            guard sig == 0x04034b50 else { break }

            let method = readUInt16(bytes, at: offset + 8)
            let compressedSize = Int(readUInt32(bytes, at: offset + 18))
            let uncompressedSize = Int(readUInt32(bytes, at: offset + 22))
            let nameLength = Int(readUInt16(bytes, at: offset + 26))
            let extraLength = Int(readUInt16(bytes, at: offset + 28))

            let nameStart = offset + 30
            guard nameStart + nameLength <= count else { throw ExtractionError.invalidData }
            let nameData = Data(bytes[nameStart..<nameStart + nameLength])
            let name = String(data: nameData, encoding: .utf8) ?? ""

            let dataStart = nameStart + nameLength + extraLength
            let dataEnd = dataStart + compressedSize
            guard dataEnd <= count else { throw ExtractionError.invalidData }

            let compressedData = Data(bytes[dataStart..<dataEnd])

            if !name.hasSuffix("/") && uncompressedSize > 0 {
                if method == 0 {
                    // Stored
                    entries[name] = compressedData
                } else if method == 8 {
                    // Deflate — use Compression framework (raw deflate)
                    if let decompressed = Self.inflateRaw(compressedData, expectedSize: uncompressedSize) {
                        entries[name] = decompressed
                    }
                }
            }

            offset = dataEnd
        }

        if entries.isEmpty && count > 0 {
            throw ExtractionError.invalidData
        }

        return entries
    }

    private static func readUInt16(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func readUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset])
        | (UInt32(bytes[offset + 1]) << 8)
        | (UInt32(bytes[offset + 2]) << 16)
        | (UInt32(bytes[offset + 3]) << 24)
    }

    private static func inflateRaw(_ data: Data, expectedSize: Int) -> Data? {
        let sourceSize = data.count
        guard sourceSize > 0 else { return nil }

        // Allocate destination buffer with some margin
        let destSize = max(expectedSize, sourceSize * 4)
        let destBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: destSize)
        defer { destBuffer.deallocate() }

        let result = data.withUnsafeBytes { (srcRaw: UnsafeRawBufferPointer) -> Int in
            guard let srcPtr = srcRaw.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return 0
            }
            return compression_decode_buffer(
                destBuffer, destSize,
                srcPtr, sourceSize,
                nil,
                COMPRESSION_ZLIB
            )
        }

        guard result > 0 else { return nil }
        return Data(bytes: destBuffer, count: result)
    }

    // MARK: - HTML Stripping

    static func stripHTML(_ html: String) -> String {
        guard !html.isEmpty else { return "" }

        var text = html

        let blockTags = ["</p>", "</div>", "</h1>", "</h2>", "</h3>", "</h4>", "</h5>", "</h6>", "<br>", "<br/>", "<br />"]
        for tag in blockTags {
            text = text.replacingOccurrences(of: tag, with: "\n", options: .caseInsensitive)
        }

        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)

        let entities: [(String, String)] = [
            ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
            ("&quot;", "\""), ("&apos;", "'"), ("&#39;", "'"),
            ("&nbsp;", " "), ("&#160;", " "), ("&mdash;", "\u{2014}"),
            ("&ndash;", "\u{2013}"), ("&hellip;", "\u{2026}"),
            ("&rsquo;", "\u{2019}"), ("&lsquo;", "\u{2018}"),
            ("&rdquo;", "\u{201D}"), ("&ldquo;", "\u{201C}"),
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }

        text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        return text
    }

    // MARK: - EPUB XML Parsing

    private func parseContainerForOPFPath(_ xml: String) -> String? {
        guard let range = xml.range(of: "full-path=\"[^\"]+\"", options: .regularExpression) else { return nil }
        let match = String(xml[range])
        return match.replacingOccurrences(of: "full-path=\"", with: "").replacingOccurrences(of: "\"", with: "")
    }

    private struct EPUBMetadata {
        let title: String?
        let author: String?
    }

    private func parseOPFMetadata(_ xml: String) -> EPUBMetadata {
        let title = extractTagContent(from: xml, tag: "dc:title")
        let author = extractTagContent(from: xml, tag: "dc:creator")
        return EPUBMetadata(title: title, author: author)
    }

    private func parseOPFSpineHrefs(_ xml: String) -> [String] {
        var manifest: [String: String] = [:]
        let manifestPattern = "<item\\s+[^>]*id=\"([^\"]+)\"[^>]*href=\"([^\"]+)\"[^>]*/>"
        if let regex = try? NSRegularExpression(pattern: manifestPattern, options: .dotMatchesLineSeparators) {
            let matches = regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml))
            for match in matches {
                if let idRange = Range(match.range(at: 1), in: xml),
                   let hrefRange = Range(match.range(at: 2), in: xml) {
                    manifest[String(xml[idRange])] = String(xml[hrefRange])
                }
            }
        }

        let manifestPattern2 = "<item\\s+[^>]*href=\"([^\"]+)\"[^>]*id=\"([^\"]+)\"[^>]*/>"
        if let regex = try? NSRegularExpression(pattern: manifestPattern2, options: .dotMatchesLineSeparators) {
            let matches = regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml))
            for match in matches {
                if let hrefRange = Range(match.range(at: 1), in: xml),
                   let idRange = Range(match.range(at: 2), in: xml) {
                    manifest[String(xml[idRange])] = String(xml[hrefRange])
                }
            }
        }

        var spineIDs: [String] = []
        let spinePattern = "<itemref\\s+idref=\"([^\"]+)\""
        if let regex = try? NSRegularExpression(pattern: spinePattern) {
            let matches = regex.matches(in: xml, range: NSRange(xml.startIndex..., in: xml))
            for match in matches {
                if let idRange = Range(match.range(at: 1), in: xml) {
                    spineIDs.append(String(xml[idRange]))
                }
            }
        }

        return spineIDs.compactMap { manifest[$0] }
    }

    private func extractTagContent(from xml: String, tag: String) -> String? {
        let pattern = "<\(tag)[^>]*>([^<]+)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: xml, range: NSRange(xml.startIndex..., in: xml)),
              let range = Range(match.range(at: 1), in: xml) else { return nil }
        return String(xml[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
