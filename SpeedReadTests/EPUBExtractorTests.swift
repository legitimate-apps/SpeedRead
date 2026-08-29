import Testing
import Foundation
import Compression
@testable import SpeedRead

@Suite("EPUB Extractor Tests")
struct EPUBExtractorTests {

    @Test func extractsTextFromXHTML() {
        let xhtml = """
        <html><body>
        <h1>Chapter One</h1>
        <p>This is a <em>test</em> paragraph.</p>
        <p>Second paragraph here.</p>
        </body></html>
        """
        let text = EPUBExtractor.stripHTML(xhtml)
        #expect(text.contains("Chapter One"))
        #expect(text.contains("This is a test paragraph."))
        #expect(text.contains("Second paragraph here."))
        #expect(!text.contains("<"))
        #expect(!text.contains(">"))
    }

    @Test func stripHTMLHandlesEntities() {
        let xhtml = "<p>Don&apos;t stop &amp; think</p>"
        let text = EPUBExtractor.stripHTML(xhtml)
        #expect(text.contains("Don't") || text.contains("Don\u{2019}t"))
        #expect(text.contains("&") || text.contains("think"))
    }

    @Test func stripHTMLHandlesEmptyInput() {
        let text = EPUBExtractor.stripHTML("")
        #expect(text.isEmpty)
    }

    @Test func invalidDataThrows() {
        let extractor = EPUBExtractor()
        #expect(throws: ExtractionError.self) {
            try extractor.extractText(from: Data("not an epub".utf8))
        }
    }

    // MARK: - End-to-end EPUB extraction

    @Test func endToEndEPUBExtraction() throws {
        let mimetype = Data("application/epub+zip".utf8)

        let containerXML = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """.utf8)

        let contentOPF = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>Test Title</dc:title>
            <dc:creator>Test Author</dc:creator>
          </metadata>
          <manifest>
            <item id="ch1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine>
            <itemref idref="ch1"/>
          </spine>
        </package>
        """.utf8)

        let chapterXHTML = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml">
        <head><title>Chapter 1</title></head>
        <body>
        <h1>Chapter One</h1>
        <p>The quick brown fox jumps over the lazy dog.</p>
        <p>Second paragraph of the test book.</p>
        </body>
        </html>
        """.utf8)

        let files: [(name: String, data: Data)] = [
            ("mimetype", mimetype),
            ("META-INF/container.xml", containerXML),
            ("content.opf", contentOPF),
            ("chapter1.xhtml", chapterXHTML),
        ]

        let epubData = buildStoredZIP(files: files)

        let extractor = EPUBExtractor()
        let result = try extractor.extractText(from: epubData)

        #expect(result.title == "Test Title")
        #expect(result.author == "Test Author")
        #expect(result.text.contains("quick brown fox"))
        #expect(result.text.contains("Second paragraph"))
        #expect(result.text.contains("Chapter One"))
    }

    @Test func recoversSpineIDRefThatNamesExistingChapter() throws {
        let epubData = makeEPUB(
            opfPath: "OEBPS/content.opf",
            opfXML: """
            <?xml version="1.0" encoding="UTF-8"?>
            <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
              <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
                <dc:title>Recoverable Spine</dc:title>
              </metadata>
              <manifest>
                <item id="ch1" href="Text/ch1.xhtml" media-type="application/xhtml+xml"/>
              </manifest>
              <spine>
                <itemref idref="ch1"/>
                <itemref idref="Text/ch2.xhtml"/>
              </spine>
            </package>
            """,
            chapters: [
                ("OEBPS/Text/ch1.xhtml", utf8Chapter("First chapter sentinel.")),
                ("OEBPS/Text/ch2.xhtml", utf8Chapter("Recovered second chapter sentinel.")),
            ]
        )

        let result = try EPUBExtractor().extractText(from: epubData)

        #expect(result.text.contains("First chapter sentinel."))
        #expect(result.text.contains("Recovered second chapter sentinel."))
    }

    @Test func resolvesParentAndCurrentDirectorySegmentsInChapterHref() throws {
        let epubData = makeEPUB(
            opfPath: "OPS/Package/content.opf",
            opfXML: standardOPF(hrefs: [("ch1", "../Text/./ch1.xhtml")]),
            chapters: [
                ("OPS/Text/ch1.xhtml", utf8Chapter("Normalized path chapter sentinel.")),
            ]
        )

        let result = try EPUBExtractor().extractText(from: epubData)

        #expect(result.text.contains("Normalized path chapter sentinel."))
    }

    @Test func missingSpineChapterEntryThrowsInsteadOfReturningPartialBook() {
        let epubData = makeEPUB(
            opfXML: standardOPF(hrefs: [
                ("ch1", "chapter1.xhtml"),
                ("ch2", "missing.xhtml"),
            ]),
            chapters: [
                ("chapter1.xhtml", utf8Chapter("Only the first chapter is present.")),
            ]
        )

        do {
            let partialResult = try EPUBExtractor().extractText(from: epubData)
            Issue.record("Expected a missing-chapter error, got partial text: \(partialResult.text)")
        } catch let error as ExtractionError {
            #expect(error == .parsingFailed("Missing spine chapter at missing.xhtml"))
        } catch {
            Issue.record("Expected ExtractionError, got \(error)")
        }
    }

    @Test func decodesChapterUsingDeclaredISO88591Encoding() throws {
        let chapter = """
        <?xml version="1.0" encoding="ISO-8859-1"?>
        <html xmlns="http://www.w3.org/1999/xhtml"><body><p>Café déjà lu.</p></body></html>
        """.data(using: .isoLatin1)!
        let epubData = makeEPUB(
            opfXML: standardOPF(hrefs: [("ch1", "chapter1.xhtml")]),
            chapters: [("chapter1.xhtml", chapter)]
        )

        let result = try EPUBExtractor().extractText(from: epubData)

        #expect(result.text.contains("Café déjà lu."))
    }

    @Test func decodesBOMlessUTF16BEChapterFromXMLDeclaration() throws {
        let chapterText = """
        <?xml version="1.0" encoding="UTF-16BE"?>
        <html xmlns="http://www.w3.org/1999/xhtml"><body><p>UTF sixteen chapter sentinel.</p></body></html>
        """
        let chapter = try #require(chapterText.data(using: .utf16BigEndian))
        let epubData = makeEPUB(
            opfXML: standardOPF(hrefs: [("ch1", "chapter1.xhtml")]),
            chapters: [("chapter1.xhtml", chapter)]
        )

        let result = try EPUBExtractor().extractText(from: epubData)

        #expect(result.text.contains("UTF sixteen chapter sentinel."))
    }

    @Test func parsesSingleQuotedManifestAndSpineAttributes() throws {
        let epubData = makeEPUB(
            opfXML: """
            <?xml version='1.0' encoding='UTF-8'?>
            <package xmlns='http://www.idpf.org/2007/opf' version='3.0'>
              <metadata xmlns:dc='http://purl.org/dc/elements/1.1/'>
                <dc:title>Single Quotes</dc:title>
                <dc:creator>Quoted Author</dc:creator>
              </metadata>
              <manifest>
                <item media-type='application/xhtml+xml' href='chapter1.xhtml' id='ch1'/>
              </manifest>
              <spine>
                <itemref linear='yes' idref='ch1'/>
              </spine>
            </package>
            """,
            chapters: [
                ("chapter1.xhtml", utf8Chapter("Single-quoted attribute sentinel.")),
            ]
        )

        let result = try EPUBExtractor().extractText(from: epubData)

        #expect(result.title == "Single Quotes")
        #expect(result.author == "Quoted Author")
        #expect(result.text.contains("Single-quoted attribute sentinel."))
    }

    @Test func unsupportedDeclaredChapterEncodingThrowsInsteadOfReturningPartialBook() {
        let unsupportedChapter = Data("""
        <?xml version="1.0" encoding="x-speedread-unsupported"?>
        <html><body><p>This must never disappear silently.</p></body></html>
        """.utf8)
        let epubData = makeEPUB(
            opfXML: standardOPF(hrefs: [
                ("ch1", "chapter1.xhtml"),
                ("ch2", "chapter2.xhtml"),
            ]),
            chapters: [
                ("chapter1.xhtml", utf8Chapter("First chapter remains decodable.")),
                ("chapter2.xhtml", unsupportedChapter),
            ]
        )

        do {
            let partialResult = try EPUBExtractor().extractText(from: epubData)
            Issue.record("Expected a decoding error, got partial text: \(partialResult.text)")
        } catch let error as ExtractionError {
            #expect(error == .parsingFailed("Could not decode spine chapter at chapter2.xhtml"))
        } catch {
            Issue.record("Expected ExtractionError, got \(error)")
        }
    }

    // MARK: - ZIP reader characterisation

    @Test func unzipReadsStoredEntriesWithoutCentralDirectory() throws {
        let first = Data("first stored payload".utf8)
        let second = Data("second stored payload".utf8)
        let archive = buildStoredZIP(
            files: [("first.txt", first), ("nested/second.txt", second)],
            includeCentralDirectory: false
        )

        let entries = try EPUBExtractor.unzipEntries(from: archive)

        #expect(entries.count == 2)
        #expect(entries["first.txt"] == first)
        #expect(entries["nested/second.txt"] == second)
    }

    @Test func unzipReadsStoredEntryWithSignedDataDescriptor() throws {
        let original = Data("descriptor-backed payload".utf8)
        let archive = buildSingleEntryZIP(
            name: "descriptor.txt",
            originalData: original,
            compressedData: original,
            method: 0,
            usesDataDescriptor: true
        )

        let entries = try EPUBExtractor.unzipEntries(from: archive)

        #expect(entries == ["descriptor.txt": original])
    }

    @Test func unzipInflatesDeflatedEntry() throws {
        let original = Data(String(repeating: "compressible chapter words ", count: 80).utf8)
        let compressed = try #require(deflateRaw(original))
        let archive = buildSingleEntryZIP(
            name: "chapter.xhtml",
            originalData: original,
            compressedData: compressed,
            method: 8,
            usesDataDescriptor: false
        )

        let entries = try EPUBExtractor.unzipEntries(from: archive)

        #expect(entries == ["chapter.xhtml": original])
    }

    @Test func unzipUsesCentralDirectoryForUnsignedDataDescriptor() throws {
        let original = Data("unsigned descriptor payload".utf8)
        let archive = buildSingleEntryZIP(
            name: "unsigned-descriptor.txt",
            originalData: original,
            compressedData: original,
            method: 0,
            usesDataDescriptor: true,
            descriptorHasSignature: false
        )

        let entries = try EPUBExtractor.unzipEntries(from: archive)

        #expect(entries == ["unsigned-descriptor.txt": original])
    }

    @Test func unzipUsesCentralDirectoryForPrefixedArchive() throws {
        let original = Data("self-extracting archive payload".utf8)
        let prefix = Data("launcher-prefix-that-is-not-a-local-header".utf8)
        let archive = buildSingleEntryZIP(
            prefix: prefix,
            name: "prefixed.txt",
            originalData: original,
            compressedData: original,
            method: 0,
            usesDataDescriptor: false
        )

        let entries = try EPUBExtractor.unzipEntries(from: archive)

        #expect(entries == ["prefixed.txt": original])
    }

    private func makeEPUB(
        opfPath: String = "content.opf",
        opfXML: String,
        chapters: [(name: String, data: Data)]
    ) -> Data {
        let containerXML = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="\(opfPath)" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """.utf8)
        let files: [(name: String, data: Data)] = [
            ("mimetype", Data("application/epub+zip".utf8)),
            ("META-INF/container.xml", containerXML),
            (opfPath, Data(opfXML.utf8)),
        ] + chapters
        return buildStoredZIP(files: files)
    }

    private func standardOPF(hrefs: [(id: String, href: String)]) -> String {
        let manifest = hrefs.map {
            "<item id=\"\($0.id)\" href=\"\($0.href)\" media-type=\"application/xhtml+xml\"/>"
        }.joined(separator: "\n")
        let spine = hrefs.map {
            "<itemref idref=\"\($0.id)\"/>"
        }.joined(separator: "\n")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>Fixture Book</dc:title>
          </metadata>
          <manifest>\(manifest)</manifest>
          <spine>\(spine)</spine>
        </package>
        """
    }

    private func utf8Chapter(_ text: String) -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <html xmlns="http://www.w3.org/1999/xhtml"><body><p>\(text)</p></body></html>
        """.utf8)
    }

    /// Builds a minimal ZIP archive using stored (no compression) method.
    private func buildStoredZIP(
        files: [(name: String, data: Data)],
        includeCentralDirectory: Bool = true
    ) -> Data {
        var archive = Data()
        var centralDirectory = Data()
        var centralEntryCount: UInt16 = 0

        for file in files {
            let nameData = Data(file.name.utf8)
            let localHeaderOffset = UInt32(archive.count)

            // Local file header
            var local = Data()
            local.appendUInt32(0x04034b50)  // signature
            local.appendUInt16(20)           // version needed
            local.appendUInt16(0)            // general purpose flag
            local.appendUInt16(0)            // compression method (stored)
            local.appendUInt16(0)            // mod time
            local.appendUInt16(0)            // mod date
            local.appendUInt32(crc32(file.data)) // CRC-32
            local.appendUInt32(UInt32(file.data.count)) // compressed size
            local.appendUInt32(UInt32(file.data.count)) // uncompressed size
            local.appendUInt16(UInt16(nameData.count))   // name length
            local.appendUInt16(0)            // extra field length
            local.append(nameData)
            local.append(file.data)
            archive.append(local)

            // Central directory entry
            var cd = Data()
            cd.appendUInt32(0x02014b50)     // signature
            cd.appendUInt16(20)              // version made by
            cd.appendUInt16(20)              // version needed
            cd.appendUInt16(0)               // general purpose flag
            cd.appendUInt16(0)               // compression method
            cd.appendUInt16(0)               // mod time
            cd.appendUInt16(0)               // mod date
            cd.appendUInt32(crc32(file.data)) // CRC-32
            cd.appendUInt32(UInt32(file.data.count)) // compressed size
            cd.appendUInt32(UInt32(file.data.count)) // uncompressed size
            cd.appendUInt16(UInt16(nameData.count))   // name length
            cd.appendUInt16(0)               // extra field length
            cd.appendUInt16(0)               // comment length
            cd.appendUInt16(0)               // disk number start
            cd.appendUInt16(0)               // internal attributes
            cd.appendUInt32(0)               // external attributes
            cd.appendUInt32(localHeaderOffset) // relative offset
            cd.append(nameData)
            centralDirectory.append(cd)
            centralEntryCount += 1
        }

        guard includeCentralDirectory else { return archive }

        let cdOffset = UInt32(archive.count)
        archive.append(centralDirectory)
        let cdSize = UInt32(centralDirectory.count)

        // End of central directory record
        var eocd = Data()
        eocd.appendUInt32(0x06054b50)       // signature
        eocd.appendUInt16(0)                 // disk number
        eocd.appendUInt16(0)                 // disk with CD
        eocd.appendUInt16(centralEntryCount) // entries on disk
        eocd.appendUInt16(centralEntryCount) // total entries
        eocd.appendUInt32(cdSize)            // CD size
        eocd.appendUInt32(cdOffset)          // CD offset
        eocd.appendUInt16(0)                 // comment length
        archive.append(eocd)

        return archive
    }

    private func buildSingleEntryZIP(
        prefix: Data = Data(),
        name: String,
        originalData: Data,
        compressedData: Data,
        method: UInt16,
        usesDataDescriptor: Bool,
        descriptorHasSignature: Bool = true
    ) -> Data {
        let nameData = Data(name.utf8)
        let checksum = crc32(originalData)
        let flags: UInt16 = usesDataDescriptor ? 0x0008 : 0

        var archive = prefix
        let localHeaderOffset = UInt32(prefix.count)
        archive.appendUInt32(0x04034b50)
        archive.appendUInt16(20)
        archive.appendUInt16(flags)
        archive.appendUInt16(method)
        archive.appendUInt16(0)
        archive.appendUInt16(0)
        archive.appendUInt32(usesDataDescriptor ? 0 : checksum)
        archive.appendUInt32(usesDataDescriptor ? 0 : UInt32(compressedData.count))
        archive.appendUInt32(usesDataDescriptor ? 0 : UInt32(originalData.count))
        archive.appendUInt16(UInt16(nameData.count))
        archive.appendUInt16(0)
        archive.append(nameData)
        archive.append(compressedData)

        if usesDataDescriptor {
            if descriptorHasSignature {
                archive.appendUInt32(0x08074b50)
            }
            archive.appendUInt32(checksum)
            archive.appendUInt32(UInt32(compressedData.count))
            archive.appendUInt32(UInt32(originalData.count))
        }

        let centralDirectoryOffset = UInt32(archive.count)
        var centralDirectory = Data()
        centralDirectory.appendUInt32(0x02014b50)
        centralDirectory.appendUInt16(20)
        centralDirectory.appendUInt16(20)
        centralDirectory.appendUInt16(flags)
        centralDirectory.appendUInt16(method)
        centralDirectory.appendUInt16(0)
        centralDirectory.appendUInt16(0)
        centralDirectory.appendUInt32(checksum)
        centralDirectory.appendUInt32(UInt32(compressedData.count))
        centralDirectory.appendUInt32(UInt32(originalData.count))
        centralDirectory.appendUInt16(UInt16(nameData.count))
        centralDirectory.appendUInt16(0)
        centralDirectory.appendUInt16(0)
        centralDirectory.appendUInt16(0)
        centralDirectory.appendUInt16(0)
        centralDirectory.appendUInt32(0)
        centralDirectory.appendUInt32(localHeaderOffset)
        centralDirectory.append(nameData)
        archive.append(centralDirectory)

        archive.appendUInt32(0x06054b50)
        archive.appendUInt16(0)
        archive.appendUInt16(0)
        archive.appendUInt16(1)
        archive.appendUInt16(1)
        archive.appendUInt32(UInt32(centralDirectory.count))
        archive.appendUInt32(centralDirectoryOffset)
        archive.appendUInt16(0)
        return archive
    }

    private func deflateRaw(_ data: Data) -> Data? {
        let destinationCapacity = max(64, data.count * 2)
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationCapacity)
        defer { destination.deallocate() }

        let encodedCount = data.withUnsafeBytes { rawBuffer -> Int in
            guard let source = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return 0
            }
            return compression_encode_buffer(
                destination,
                destinationCapacity,
                source,
                data.count,
                nil,
                COMPRESSION_ZLIB
            )
        }
        guard encodedCount > 0 else { return nil }
        return Data(bytes: destination, count: encodedCount)
    }

    /// Simple CRC-32 implementation for test use.
    private func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ 0xEDB88320
                } else {
                    crc >>= 1
                }
            }
        }
        return crc ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func appendUInt16(_ value: UInt16) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: 2))
    }
    mutating func appendUInt32(_ value: UInt32) {
        var v = value.littleEndian
        append(Data(bytes: &v, count: 4))
    }
}
