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

        var spineDocuments: [SpineDocument] = []
        var startWordIndex = 0
        for spineID in package.spineIDs {
            let href: String
            if let manifestItem = package.manifest[spineID] {
                href = manifestItem.href
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
            let text = Self.stripHTML(xhtml)
            spineDocuments.append(SpineDocument(
                path: chapterPath,
                source: xhtml,
                text: text,
                startWordIndex: startWordIndex
            ))
            startWordIndex += Book.tokenize(text).count
        }

        // This is the legacy text assembly. Chapter extraction is metadata-only:
        // it must never participate in, trim, or otherwise alter this join.
        let fullText = spineDocuments.map(\.text).joined(separator: "\n\n")
        let chapters = try Self.chapterMarks(
            package: package,
            entries: entries,
            opfDirectory: opfDirectory,
            spineDocuments: spineDocuments,
            wordCount: startWordIndex
        )

        return ExtractionResult(
            text: fullText,
            title: package.title,
            author: package.author,
            chapters: chapters
        )
    }

    // MARK: - Minimal ZIP Reader

    /// Reads all entries from a ZIP archive into memory.
    /// Supports Store (method 0) and Deflate (method 8).
    static func unzipEntries(from data: Data) throws -> [String: Data] {
        let bytes = [UInt8](data)
        guard !bytes.isEmpty else { throw ExtractionError.invalidData }

        let entries: [String: Data]
        if let centralDirectory = try readCentralDirectory(in: bytes) {
            entries = try extractCentralDirectoryEntries(centralDirectory, from: bytes)
        } else {
            entries = try extractLocalHeaderEntries(from: bytes)
        }

        guard !entries.isEmpty else { throw ExtractionError.invalidData }
        return entries
    }

    private struct ZIPCentralEntry {
        let name: String
        let flags: UInt16
        let method: UInt16
        let checksum: UInt32
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    private static func readCentralDirectory(in bytes: [UInt8]) throws -> [ZIPCentralEntry]? {
        guard bytes.count >= 22 else { return nil }

        let earliestEOCD = max(0, bytes.count - 22 - Int(UInt16.max))
        var endOffset = bytes.count - 22
        var eocdOffset: Int?
        while endOffset >= earliestEOCD {
            if readUInt32(bytes, at: endOffset) == 0x06054b50 {
                let commentLength = Int(readUInt16(bytes, at: endOffset + 20))
                if endOffset + 22 + commentLength <= bytes.count {
                    eocdOffset = endOffset
                    break
                }
            }
            endOffset -= 1
        }

        guard let eocdOffset else { return nil }
        let diskNumber = readUInt16(bytes, at: eocdOffset + 4)
        let directoryDisk = readUInt16(bytes, at: eocdOffset + 6)
        let entriesOnDisk = readUInt16(bytes, at: eocdOffset + 8)
        let totalEntries = readUInt16(bytes, at: eocdOffset + 10)
        guard diskNumber == 0,
              directoryDisk == 0,
              entriesOnDisk == totalEntries,
              totalEntries != UInt16.max else {
            throw ExtractionError.invalidData
        }

        let directorySize = Int(readUInt32(bytes, at: eocdOffset + 12))
        let directoryOffset = Int(readUInt32(bytes, at: eocdOffset + 16))
        guard directoryOffset <= bytes.count,
              directorySize <= bytes.count - directoryOffset,
              directoryOffset + directorySize <= eocdOffset else {
            throw ExtractionError.invalidData
        }

        var entries: [ZIPCentralEntry] = []
        entries.reserveCapacity(Int(totalEntries))
        var offset = directoryOffset
        for _ in 0..<totalEntries {
            guard offset + 46 <= bytes.count,
                  readUInt32(bytes, at: offset) == 0x02014b50 else {
                throw ExtractionError.invalidData
            }

            let flags = readUInt16(bytes, at: offset + 8)
            let method = readUInt16(bytes, at: offset + 10)
            let checksum = readUInt32(bytes, at: offset + 16)
            let compressedSize32 = readUInt32(bytes, at: offset + 20)
            let uncompressedSize32 = readUInt32(bytes, at: offset + 24)
            let nameLength = Int(readUInt16(bytes, at: offset + 28))
            let extraLength = Int(readUInt16(bytes, at: offset + 30))
            let commentLength = Int(readUInt16(bytes, at: offset + 32))
            let localHeaderOffset32 = readUInt32(bytes, at: offset + 42)
            guard compressedSize32 != UInt32.max,
                  uncompressedSize32 != UInt32.max,
                  localHeaderOffset32 != UInt32.max else {
                throw ExtractionError.invalidData
            }

            let nameStart = offset + 46
            let recordEnd = nameStart + nameLength + extraLength + commentLength
            guard recordEnd <= bytes.count else { throw ExtractionError.invalidData }
            let name = try decodeZIPEntryName(
                bytes[nameStart..<(nameStart + nameLength)],
                isUTF8: flags & 0x0800 != 0
            )

            entries.append(ZIPCentralEntry(
                name: name,
                flags: flags,
                method: method,
                checksum: checksum,
                compressedSize: Int(compressedSize32),
                uncompressedSize: Int(uncompressedSize32),
                localHeaderOffset: Int(localHeaderOffset32)
            ))
            offset = recordEnd
        }

        guard offset == directoryOffset + directorySize else {
            throw ExtractionError.invalidData
        }
        return entries
    }

    private static func extractCentralDirectoryEntries(
        _ directory: [ZIPCentralEntry],
        from bytes: [UInt8]
    ) throws -> [String: Data] {
        var entries: [String: Data] = [:]
        entries.reserveCapacity(directory.count)

        for entry in directory {
            guard entry.flags & 0x0001 == 0,
                  entry.localHeaderOffset + 30 <= bytes.count,
                  readUInt32(bytes, at: entry.localHeaderOffset) == 0x04034b50 else {
                throw ExtractionError.invalidData
            }

            let localNameLength = Int(readUInt16(bytes, at: entry.localHeaderOffset + 26))
            let localExtraLength = Int(readUInt16(bytes, at: entry.localHeaderOffset + 28))
            let dataStart = entry.localHeaderOffset + 30 + localNameLength + localExtraLength
            guard dataStart <= bytes.count,
                  entry.compressedSize <= bytes.count - dataStart else {
                throw ExtractionError.invalidData
            }

            if entry.name.hasSuffix("/") { continue }
            let compressedData = Data(bytes[dataStart..<(dataStart + entry.compressedSize)])
            let extracted = try extractZIPPayload(
                compressedData,
                method: entry.method,
                expectedSize: entry.uncompressedSize
            )
            guard extracted.count == entry.uncompressedSize,
                  crc32(extracted) == entry.checksum,
                  entries.updateValue(extracted, forKey: entry.name) == nil else {
                throw ExtractionError.invalidData
            }
        }
        return entries
    }

    private static func extractLocalHeaderEntries(from bytes: [UInt8]) throws -> [String: Data] {
        var entries: [String: Data] = [:]
        var offset = 0

        while offset + 30 <= bytes.count {
            guard readUInt32(bytes, at: offset) == 0x04034b50 else { break }
            let flags = readUInt16(bytes, at: offset + 6)
            let method = readUInt16(bytes, at: offset + 8)
            var checksum = readUInt32(bytes, at: offset + 14)
            var compressedSize = Int(readUInt32(bytes, at: offset + 18))
            var uncompressedSize = Int(readUInt32(bytes, at: offset + 22))
            let nameLength = Int(readUInt16(bytes, at: offset + 26))
            let extraLength = Int(readUInt16(bytes, at: offset + 28))
            let nameStart = offset + 30
            let dataStart = nameStart + nameLength + extraLength
            guard flags & 0x0001 == 0,
                  nameStart + nameLength <= bytes.count,
                  dataStart <= bytes.count else {
                throw ExtractionError.invalidData
            }

            let name = try decodeZIPEntryName(
                bytes[nameStart..<(nameStart + nameLength)],
                isUTF8: flags & 0x0800 != 0
            )
            let hasDescriptor = flags & 0x0008 != 0
            var descriptorLength = 0
            if hasDescriptor && compressedSize == 0 && uncompressedSize == 0 {
                guard let descriptorOffset = firstSignature(
                    0x08074b50,
                    in: bytes,
                    startingAt: dataStart
                ), descriptorOffset + 16 <= bytes.count else {
                    throw ExtractionError.invalidData
                }
                checksum = readUInt32(bytes, at: descriptorOffset + 4)
                compressedSize = Int(readUInt32(bytes, at: descriptorOffset + 8))
                uncompressedSize = Int(readUInt32(bytes, at: descriptorOffset + 12))
                guard dataStart + compressedSize == descriptorOffset else {
                    throw ExtractionError.invalidData
                }
                descriptorLength = 16
            } else if hasDescriptor {
                descriptorLength = dataStart + compressedSize + 4 <= bytes.count
                    && readUInt32(bytes, at: dataStart + compressedSize) == 0x08074b50
                    ? 16 : 12
            }

            guard compressedSize <= bytes.count - dataStart else {
                throw ExtractionError.invalidData
            }
            if hasDescriptor {
                let descriptorStart = dataStart + compressedSize
                guard descriptorLength <= bytes.count - descriptorStart else {
                    throw ExtractionError.invalidData
                }
                let fieldsStart = descriptorStart + (descriptorLength == 16 ? 4 : 0)
                guard readUInt32(bytes, at: fieldsStart) == checksum,
                      Int(readUInt32(bytes, at: fieldsStart + 4)) == compressedSize,
                      Int(readUInt32(bytes, at: fieldsStart + 8)) == uncompressedSize else {
                    throw ExtractionError.invalidData
                }
            }
            if !name.hasSuffix("/") {
                let compressedData = Data(bytes[dataStart..<(dataStart + compressedSize)])
                let extracted = try extractZIPPayload(
                    compressedData,
                    method: method,
                    expectedSize: uncompressedSize
                )
                guard extracted.count == uncompressedSize,
                      crc32(extracted) == checksum,
                      entries.updateValue(extracted, forKey: name) == nil else {
                    throw ExtractionError.invalidData
                }
            }
            offset = dataStart + compressedSize + descriptorLength
        }
        return entries
    }

    private static func decodeZIPEntryName(
        _ bytes: ArraySlice<UInt8>,
        isUTF8: Bool
    ) throws -> String {
        let data = Data(bytes)
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        guard !isUTF8, let legacy = String(data: data, encoding: .isoLatin1) else {
            throw ExtractionError.invalidData
        }
        return legacy
    }

    private static func extractZIPPayload(
        _ compressedData: Data,
        method: UInt16,
        expectedSize: Int
    ) throws -> Data {
        switch method {
        case 0:
            return compressedData
        case 8:
            if expectedSize == 0 { return Data() }
            guard let inflated = inflateRaw(compressedData, expectedSize: expectedSize) else {
                throw ExtractionError.invalidData
            }
            return inflated
        default:
            throw ExtractionError.invalidData
        }
    }

    private static func firstSignature(
        _ signature: UInt32,
        in bytes: [UInt8],
        startingAt start: Int
    ) -> Int? {
        guard start <= bytes.count - 4 else { return nil }
        for offset in start...(bytes.count - 4) where readUInt32(bytes, at: offset) == signature {
            return offset
        }
        return nil
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var checksum: UInt32 = 0xFFFF_FFFF
        for byte in data {
            checksum ^= UInt32(byte)
            for _ in 0..<8 {
                checksum = checksum & 1 == 0
                    ? checksum >> 1
                    : (checksum >> 1) ^ 0xEDB8_8320
            }
        }
        return checksum ^ 0xFFFF_FFFF
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

        // The head (title, style sheets) and any style or script element are not the book's text.
        var text = html.replacingOccurrences(
            of: "(?is)<(head|style|script)\\b[^>]*>.*?</\\1\\s*>", with: "", options: .regularExpression
        )

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
        let manifest: [String: EPUBManifestItem]
        let spineIDs: [String]
        let spineTOCID: String?
    }

    fileprivate struct EPUBManifestItem {
        let href: String
        let mediaType: String?
        let properties: Set<String>
    }

    private struct SpineDocument {
        let path: String
        let source: String
        let text: String
        let startWordIndex: Int
    }

    fileprivate struct NavigationEntry {
        let title: String
        let reference: String
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
            spineIDs: delegate.spineIDs,
            spineTOCID: delegate.spineTOCID
        )
    }

    private static func chapterMarks(
        package: EPUBPackage,
        entries: [String: Data],
        opfDirectory: String,
        spineDocuments: [SpineDocument],
        wordCount: Int
    ) throws -> [ChapterMark] {
        let navigationItem = package.manifest.values.first {
            $0.properties.contains("nav")
        } ?? package.spineTOCID.flatMap { package.manifest[$0] }
            ?? package.manifest.values.first { $0.mediaType == "application/x-dtbncx+xml" }

        if let navigationItem {
            let navigationPath = try resolveArchivePath(
                navigationItem.href,
                relativeTo: opfDirectory
            )
            if let navigationData = entries[navigationPath] {
                let navigationDirectory = navigationPath.split(separator: "/")
                    .dropLast().joined(separator: "/")
                let parsedEntries = navigationItem.mediaType == "application/x-dtbncx+xml"
                    ? parseNCXNavigation(navigationData)
                    : parseEPUB3Navigation(navigationData)
                let marks = marks(
                    for: parsedEntries,
                    relativeTo: navigationDirectory,
                    spineDocuments: spineDocuments,
                    wordCount: wordCount
                )
                if !marks.isEmpty { return marks }
            }
        }

        return headingMarks(in: spineDocuments, wordCount: wordCount)
    }

    private static func parseEPUB3Navigation(_ data: Data) -> [NavigationEntry] {
        let delegate = EPUB3NavigationXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        return parser.parse() ? delegate.entries : []
    }

    private static func parseNCXNavigation(_ data: Data) -> [NavigationEntry] {
        let delegate = NCXNavigationXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        return parser.parse() ? delegate.entries : []
    }

    private static func marks(
        for entries: [NavigationEntry],
        relativeTo navigationDirectory: String,
        spineDocuments: [SpineDocument],
        wordCount: Int
    ) -> [ChapterMark] {
        var positioned: [(order: Int, mark: ChapterMark)] = []
        for (order, entry) in entries.enumerated() {
            guard let targetPath = try? resolveArchivePath(
                entry.reference,
                relativeTo: navigationDirectory
            ), let document = spineDocuments.first(where: { $0.path == targetPath }) else {
                continue
            }

            let fragment = entry.reference.split(
                separator: "#",
                maxSplits: 1,
                omittingEmptySubsequences: false
            ).dropFirst().first.flatMap { String($0).removingPercentEncoding }
            let localOffset: Int
            if let fragment, !fragment.isEmpty {
                guard let offset = wordOffset(ofFragment: fragment, in: document.source) else {
                    continue
                }
                localOffset = offset
            } else {
                localOffset = 0
            }

            let title = normalizedTitle(entry.title)
            let index = document.startWordIndex + localOffset
            guard !title.isEmpty, index >= 0, index < wordCount else { continue }
            positioned.append((order, ChapterMark(title: title, startWordIndex: index)))
        }
        return normalizedMarks(positioned)
    }

    private static func headingMarks(
        in spineDocuments: [SpineDocument],
        wordCount: Int
    ) -> [ChapterMark] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<h([1-6])\b[^>]*>(.*?)</h\1\s*>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }

        var positioned: [(order: Int, mark: ChapterMark)] = []
        var order = 0
        for document in spineDocuments {
            let range = NSRange(document.source.startIndex..., in: document.source)
            for match in regex.matches(in: document.source, range: range) {
                guard let headingRange = Range(match.range(at: 2), in: document.source),
                      let elementRange = Range(match.range(at: 0), in: document.source) else {
                    continue
                }
                let title = normalizedTitle(stripHTML(String(document.source[headingRange])))
                let prefix = String(document.source[..<elementRange.lowerBound])
                let index = document.startWordIndex + Book.tokenize(stripHTML(prefix)).count
                guard !title.isEmpty, index < wordCount else { continue }
                positioned.append((order, ChapterMark(title: title, startWordIndex: index)))
                order += 1
            }
        }
        return normalizedMarks(positioned)
    }

    private static func wordOffset(ofFragment fragment: String, in source: String) -> Int? {
        let escaped = NSRegularExpression.escapedPattern(for: fragment)
        let pattern = #"<[^>]*\b(?:id|xml:id|name)\s*=\s*(?:\""#
            + escaped + #"\"|'"# + escaped + #"')[^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(
                in: source,
                range: NSRange(source.startIndex..., in: source)
              ),
              let range = Range(match.range, in: source) else {
            return nil
        }
        return Book.tokenize(stripHTML(String(source[..<range.lowerBound]))).count
    }

    private static func normalizedTitle(_ title: String) -> String {
        title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func normalizedMarks(
        _ positioned: [(order: Int, mark: ChapterMark)]
    ) -> [ChapterMark] {
        var seen: Set<ChapterMark> = []
        return positioned
            .sorted {
                if $0.mark.startWordIndex == $1.mark.startWordIndex {
                    return $0.order < $1.order
                }
                return $0.mark.startWordIndex < $1.mark.startWordIndex
            }
            .compactMap { seen.insert($0.mark).inserted ? $0.mark : nil }
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
        let projectedASCII = data.prefix(512).compactMap { byte -> UInt8? in
            if byte == 0 { return nil }
            return byte < 0x80 ? byte : UInt8(ascii: " ")
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
    private(set) var manifest: [String: EPUBExtractor.EPUBManifestItem] = [:]
    private(set) var spineIDs: [String] = []
    private(set) var spineTOCID: String?
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
                manifest[id] = EPUBExtractor.EPUBManifestItem(
                    href: href,
                    mediaType: attributeDict["media-type"],
                    properties: Set(
                        (attributeDict["properties"] ?? "")
                            .split(whereSeparator: \.isWhitespace)
                            .map(String.init)
                    )
                )
            }
        case "spine":
            spineTOCID = attributeDict["toc"]
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

private final class EPUB3NavigationXMLDelegate: NSObject, XMLParserDelegate {
    private(set) var entries: [EPUBExtractor.NavigationEntry] = []
    private var tocDepth: Int?
    private var depth = 0
    private var activeReference: String?
    private var activeTitle = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        depth += 1
        let localName = String(elementName.split(separator: ":").last ?? Substring(elementName))
        if localName == "nav" {
            let type = attributeDict.first {
                $0.key.split(separator: ":").last == "type"
            }?.value
            if type?.split(whereSeparator: \.isWhitespace).contains("toc") == true {
                tocDepth = depth
            }
        } else if localName == "a", tocDepth != nil, let href = attributeDict["href"] {
            activeReference = href
            activeTitle = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard activeReference != nil else { return }
        activeTitle += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let localName = String(elementName.split(separator: ":").last ?? Substring(elementName))
        if localName == "a", let reference = activeReference {
            entries.append(.init(title: activeTitle, reference: reference))
            activeReference = nil
            activeTitle = ""
        }
        if localName == "nav", tocDepth == depth { tocDepth = nil }
        depth -= 1
    }
}

private final class NCXNavigationXMLDelegate: NSObject, XMLParserDelegate {
    private struct Point {
        var title = ""
        var isCapturingTitle = false
    }

    private(set) var entries: [EPUBExtractor.NavigationEntry] = []
    private var points: [Point] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let localName = String(elementName.split(separator: ":").last ?? Substring(elementName))
        switch localName {
        case "navPoint":
            points.append(Point())
        case "text":
            if !points.isEmpty { points[points.count - 1].isCapturingTitle = true }
        case "content":
            if let source = attributeDict["src"], let point = points.last {
                entries.append(.init(title: point.title, reference: source))
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard !points.isEmpty, points[points.count - 1].isCapturingTitle else { return }
        points[points.count - 1].title += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let localName = String(elementName.split(separator: ":").last ?? Substring(elementName))
        if localName == "text", !points.isEmpty {
            points[points.count - 1].isCapturingTitle = false
        } else if localName == "navPoint", !points.isEmpty {
            points.removeLast()
        }
    }
}
