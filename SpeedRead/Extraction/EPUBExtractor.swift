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

        guard let containerData = entries["META-INF/container.xml"] else {
            throw ExtractionError.parsingFailed("Missing META-INF/container.xml")
        }

        let containerOPFPath = try Self.parseContainerForOPFPath(containerData)
        let opfPath = try Self.resolveArchivePath(containerOPFPath, relativeTo: "")

        guard let opfData = entries[opfPath] else {
            throw ExtractionError.parsingFailed("Could not read OPF file at \(opfPath)")
        }

        let opfDirectory = opfPath.split(separator: "/").dropLast().joined(separator: "/")
        let package = try Self.parseOPFPackage(opfData)
        guard !package.spineIDs.isEmpty else {
            throw ExtractionError.parsingFailed("OPF spine contains no chapters")
        }

        var chapters: [String] = []
        for spineID in package.spineIDs {
            let href: String
            if let manifestHref = package.manifest[spineID] {
                href = manifestHref
            } else {
                // Some malformed-but-recoverable books put the chapter href directly
                // in idref. Recover only when that exact resolved entry exists.
                let recoveredPath = try Self.resolveArchivePath(spineID, relativeTo: opfDirectory)
                guard entries[recoveredPath] != nil else {
                    throw ExtractionError.parsingFailed(
                        "Spine item '\(spineID)' is missing from the manifest"
                    )
                }
                href = spineID
            }

            let chapterPath = try Self.resolveArchivePath(href, relativeTo: opfDirectory)
            guard let fileData = entries[chapterPath] else {
                throw ExtractionError.parsingFailed("Missing spine chapter at \(chapterPath)")
            }
            guard let xhtml = Self.decodeXMLText(fileData) else {
                throw ExtractionError.parsingFailed("Could not decode spine chapter at \(chapterPath)")
            }
            chapters.append(Self.stripHTML(xhtml))
        }

        let fullText = chapters.joined(separator: "\n\n")

        return ExtractionResult(
            text: fullText,
            title: package.title,
            author: package.author
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

            let generalFlag = readUInt16(bytes, at: offset + 6)
            let hasDataDescriptor = (generalFlag & 0x0008) != 0
            let method = readUInt16(bytes, at: offset + 8)
            var compressedSize = Int(readUInt32(bytes, at: offset + 18))
            var uncompressedSize = Int(readUInt32(bytes, at: offset + 22))
            let nameLength = Int(readUInt16(bytes, at: offset + 26))
            let extraLength = Int(readUInt16(bytes, at: offset + 28))

            let nameStart = offset + 30
            guard nameStart + nameLength <= count else { throw ExtractionError.invalidData }
            let nameData = Data(bytes[nameStart..<nameStart + nameLength])
            let name = String(data: nameData, encoding: .utf8) ?? ""

            let dataStart = nameStart + nameLength + extraLength

            // Handle data descriptor (bit 3): sizes may be zero in local header
            if hasDataDescriptor && compressedSize == 0 && uncompressedSize == 0 {
                // Scan forward for data descriptor signature 0x08074b50
                var scanOffset = dataStart
                var found = false
                while scanOffset + 16 <= count {
                    if readUInt32(bytes, at: scanOffset) == 0x08074b50 {
                        // Data descriptor: signature(4) + crc32(4) + compressedSize(4) + uncompressedSize(4)
                        compressedSize = Int(readUInt32(bytes, at: scanOffset + 8))
                        uncompressedSize = Int(readUInt32(bytes, at: scanOffset + 12))
                        found = true
                        break
                    }
                    scanOffset += 1
                }
                if !found {
                    offset = dataStart
                    continue
                }
            }

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

            // Advance past data descriptor if present
            if hasDataDescriptor {
                // Check for signature-based descriptor (16 bytes) or without signature (12 bytes)
                if dataEnd + 4 <= count && readUInt32(bytes, at: dataEnd) == 0x08074b50 {
                    offset = dataEnd + 16
                } else {
                    offset = dataEnd + 12
                }
            } else {
                offset = dataEnd
            }
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

    private struct EPUBPackage {
        let title: String?
        let author: String?
        let manifest: [String: String]
        let spineIDs: [String]
    }

    private static func parseContainerForOPFPath(_ data: Data) throws -> String {
        let delegate = ContainerXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), let path = delegate.opfPath, !path.isEmpty else {
            throw ExtractionError.parsingFailed("Could not find OPF path in container.xml")
        }
        return path
    }

    private static func parseOPFPackage(_ data: Data) throws -> EPUBPackage {
        let delegate = OPFXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else {
            throw ExtractionError.parsingFailed("Could not parse OPF file")
        }
        return EPUBPackage(
            title: delegate.title,
            author: delegate.author,
            manifest: delegate.manifest,
            spineIDs: delegate.spineIDs
        )
    }

    private static func resolveArchivePath(_ reference: String, relativeTo directory: String) throws -> String {
        let resourceReference = reference
            .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
            .split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0]
        guard let decoded = String(resourceReference).removingPercentEncoding else {
            throw ExtractionError.parsingFailed("Invalid percent encoding in EPUB path '\(reference)'")
        }

        var components = decoded.hasPrefix("/")
            ? []
            : directory.split(separator: "/").map(String.init)

        for component in decoded.split(separator: "/", omittingEmptySubsequences: false) {
            switch component {
            case "", ".":
                continue
            case "..":
                guard !components.isEmpty else {
                    throw ExtractionError.parsingFailed("EPUB path escapes archive root: \(reference)")
                }
                components.removeLast()
            default:
                components.append(String(component))
            }
        }

        guard !components.isEmpty else {
            throw ExtractionError.parsingFailed("EPUB path resolves to archive root: \(reference)")
        }
        return components.joined(separator: "/")
    }

    private static func decodeXMLText(_ data: Data) -> String? {
        if let declaredName = declaredXMLEncoding(in: data) {
            guard let encoding = stringEncoding(named: declaredName) else { return nil }
            return String(data: data, encoding: encoding)?.replacingOccurrences(of: "\u{FEFF}", with: "")
        }

        let fallbackEncodings: [String.Encoding] = [.utf8, .utf16, .isoLatin1, .macOSRoman]
        for encoding in fallbackEncodings {
            if let decoded = String(data: data, encoding: encoding) {
                return decoded.replacingOccurrences(of: "\u{FEFF}", with: "")
            }
        }
        return nil
    }

    private static func declaredXMLEncoding(in data: Data) -> String? {
        let projectedASCII = data.prefix(512).map { byte in
            byte == 0 ? UInt8(ascii: " ") : (byte < 0x80 ? byte : UInt8(ascii: " "))
        }
        let prolog = String(decoding: projectedASCII, as: UTF8.self)
        let pattern = #"<\?xml[^>]*encoding\s*=\s*['\"]([^'\"]+)['\"]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: prolog, range: NSRange(prolog.startIndex..., in: prolog)),
              let range = Range(match.range(at: 1), in: prolog) else {
            return nil
        }
        return String(prolog[range])
    }

    private static func stringEncoding(named name: String) -> String.Encoding? {
        switch name.lowercased().replacingOccurrences(of: "_", with: "-") {
        case "utf-8", "utf8":
            return .utf8
        case "utf-16", "utf16":
            return .utf16
        case "utf-16le", "utf16le":
            return .utf16LittleEndian
        case "utf-16be", "utf16be":
            return .utf16BigEndian
        case "iso-8859-1", "iso8859-1", "latin1", "iso-latin-1":
            return .isoLatin1
        case "windows-1252", "cp1252":
            return .windowsCP1252
        case "macintosh", "macroman", "mac-roman", "x-mac-roman":
            return .macOSRoman
        case "us-ascii", "ascii":
            return .ascii
        default:
            return nil
        }
    }
}

private final class ContainerXMLDelegate: NSObject, XMLParserDelegate {
    private(set) var opfPath: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName.split(separator: ":").last == "rootfile",
              opfPath == nil else { return }
        opfPath = attributeDict["full-path"]
    }
}

private final class OPFXMLDelegate: NSObject, XMLParserDelegate {
    private(set) var title: String?
    private(set) var author: String?
    private(set) var manifest: [String: String] = [:]
    private(set) var spineIDs: [String] = []
    private var capturedMetadataElement: String?
    private var capturedCharacters = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let localName = String(elementName.split(separator: ":").last ?? Substring(elementName))
        switch localName {
        case "item":
            if let id = attributeDict["id"], let href = attributeDict["href"] {
                manifest[id] = href
            }
        case "itemref":
            if let idref = attributeDict["idref"] {
                spineIDs.append(idref)
            }
        case "title", "creator":
            capturedMetadataElement = localName
            capturedCharacters = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard capturedMetadataElement != nil else { return }
        capturedCharacters += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let localName = String(elementName.split(separator: ":").last ?? Substring(elementName))
        guard localName == capturedMetadataElement else { return }
        let value = capturedCharacters.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty {
            if localName == "title", title == nil {
                title = value
            } else if localName == "creator", author == nil {
                author = value
            }
        }
        capturedMetadataElement = nil
        capturedCharacters = ""
    }
}
