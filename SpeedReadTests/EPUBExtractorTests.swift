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

    @Test func navigationDocumentProducesRealTitlesAtExistingTokenOffsets() throws {
        let firstChapter = Data("""
        <html xmlns="http://www.w3.org/1999/xhtml"><body>
        <h1 id="opening">Opening</h1><p>zero one</p>
        <h2 id="middle">Middle Matters</h2><p>two three</p>
        </body></html>
        """.utf8)
        let secondChapter = Data("""
        <html xmlns="http://www.w3.org/1999/xhtml"><body>
        <h1 id="ending">The Ending</h1><p>four five</p>
        </body></html>
        """.utf8)
        let navigation = Data("""
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
        <body><nav epub:type="toc"><ol>
          <li><a href="Text/one.xhtml#opening">Opening</a></li>
          <li><a href="Text/one.xhtml#middle"><span>Middle</span> Matters</a></li>
          <li><a href="Text/two.xhtml#ending">The Ending</a></li>
        </ol></nav></body></html>
        """.utf8)
        let epubData = makeEPUB(
            opfPath: "OPS/content.opf",
            opfXML: """
            <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
              <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Chapters</dc:title></metadata>
              <manifest>
                <item id="one" href="Text/one.xhtml" media-type="application/xhtml+xml"/>
                <item id="two" href="Text/two.xhtml" media-type="application/xhtml+xml"/>
                <item id="nav" href="toc.xhtml" media-type="application/xhtml+xml" properties="nav"/>
              </manifest>
              <spine><itemref idref="one"/><itemref idref="two"/></spine>
            </package>
            """,
            chapters: [
                ("OPS/Text/one.xhtml", firstChapter),
                ("OPS/Text/two.xhtml", secondChapter),
                ("OPS/toc.xhtml", navigation)
            ]
        )

        let result = try EPUBExtractor().extractText(from: epubData)
        let legacyText = [
            EPUBExtractor.stripHTML(String(decoding: firstChapter, as: UTF8.self)),
            EPUBExtractor.stripHTML(String(decoding: secondChapter, as: UTF8.self))
        ].joined(separator: "\n\n")

        #expect(result.text == legacyText)
        #expect(result.chapters == [
            ChapterMark(title: "Opening", startWordIndex: 0),
            ChapterMark(title: "Middle Matters", startWordIndex: 3),
            ChapterMark(title: "The Ending", startWordIndex: 7)
        ])
    }

    @Test func epubWithoutNavigationOrHeadingsEmitsNoChapters() throws {
        let epubData = makeEPUB(
            opfXML: standardOPF(hrefs: [("ch1", "chapter1.xhtml")]),
            chapters: [("chapter1.xhtml", utf8Chapter("Ordinary body text."))]
        )

        let result = try EPUBExtractor().extractText(from: epubData)

        #expect(result.chapters.isEmpty)
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

    // Leg 25: mutate the bundled Gutenberg archive; these are deliberately corrupt
    // inputs, not independently invented examples of a valid EPUB/ZIP grammar.
    @Test(arguments: ["disk", "directoryDisk", "entryCount", "zip64Count", "directorySize",
                      "directoryOffset", "centralSignature", "zip64Compressed", "zip64Expanded",
                      "zip64Offset", "recordEnd", "encrypted", "localOffset", "localSignature",
                      "payloadStart", "payloadEnd", "method", "checksum", "expandedSize", "utf8Name"])
    func sampledArchiveRejectsCorruptDirectory(field: String) throws {
        var archive = try sampledArchive()
        let eocd = try #require(archive.range(of: Data([0x50, 0x4b, 0x05, 0x06]), options: .backwards)?.lowerBound)
        let central = littleEndian(archive, at: eocd + 16)
        switch field {
        case "disk": patch(&archive, at: eocd + 4, value: 1, width: 2)
        case "directoryDisk": patch(&archive, at: eocd + 6, value: 1, width: 2)
        case "entryCount": patch(&archive, at: eocd + 8, value: 0, width: 2)
        case "zip64Count":
            patch(&archive, at: eocd + 8, value: 65535, width: 2)
            patch(&archive, at: eocd + 10, value: 65535, width: 2)
        case "directorySize": patch(&archive, at: eocd + 12, value: 1)
        case "directoryOffset": patch(&archive, at: eocd + 16, value: UInt32.max)
        case "centralSignature": archive[central] = 0
        case "zip64Compressed": patch(&archive, at: central + 20, value: UInt32.max)
        case "zip64Expanded": patch(&archive, at: central + 24, value: UInt32.max)
        case "zip64Offset": patch(&archive, at: central + 42, value: UInt32.max)
        case "recordEnd": patch(&archive, at: central + 28, value: 65535, width: 2)
        case "encrypted": patch(&archive, at: central + 8, value: 1, width: 2)
        case "localOffset": patch(&archive, at: central + 42, value: UInt32(archive.count))
        case "localSignature": archive[0] = 0
        case "payloadStart":
            // Point to the final local header and extend its extra field beyond EOF.
            let last = try #require(archive.range(of: Data([0x50, 0x4b, 0x03, 0x04]), options: .backwards)?.lowerBound)
            patch(&archive, at: last + 28, value: 65535, width: 2)
        case "payloadEnd": patch(&archive, at: central + 20, value: UInt32(archive.count))
        case "method": patch(&archive, at: central + 10, value: 99, width: 2)
        case "checksum": patch(&archive, at: central + 16, value: 0)
        case "expandedSize": patch(&archive, at: central + 24, value: 18)
        case "utf8Name":
            patch(&archive, at: central + 8, value: 0x0800, width: 2)
            archive[central + 46] = 0xff
        default: Issue.record("Unknown corruption: \(field)")
        }
        // Catches accepting this corruption (including silently falling back to local headers).
        #expect(throws: ExtractionError.invalidData) {
            try EPUBExtractor.unzipEntries(from: archive)
        }
        #expect(throws: ExtractionError.invalidData) {
            try EPUBExtractor().extractText(from: archive)
        }
    }

    @Test(arguments: ["encrypted", "nameEnd", "payloadEnd", "checksum", "method", "descriptorMissing", "descriptorShort", "descriptorMismatch"])
    func sampledLocalHeaderRejectsCorruption(field: String) throws {
        let sample = try sampledArchive()
        // The first entry is the actual stored EPUB mimetype; retain its exact header/data.
        #expect(String(decoding: sample[30..<38], as: UTF8.self) == "mimetype")
        var archive = Data(sample.prefix(58))
        #expect(try EPUBExtractor.unzipEntries(from: archive) == ["mimetype": Data("application/epub+zip".utf8)])
        switch field {
        case "encrypted": patch(&archive, at: 6, value: 1, width: 2)
        case "nameEnd": patch(&archive, at: 26, value: 65535, width: 2)
        case "payloadEnd": patch(&archive, at: 18, value: 1000)
        case "checksum": patch(&archive, at: 14, value: 0)
        case "method": patch(&archive, at: 8, value: 99, width: 2)
        default:
            patch(&archive, at: 6, value: 8, width: 2)
            patch(&archive, at: 18, value: 0)
            patch(&archive, at: 22, value: 0)
            if field != "descriptorMissing" { archive.append(contentsOf: [0x50, 0x4b, 0x07, 0x08]) }
            if field == "descriptorMismatch" { archive.append(Data(repeating: 0, count: 12)) }
        }
        #expect(throws: ExtractionError.invalidData) { try EPUBExtractor.unzipEntries(from: archive) }
    }

    @Test(arguments: ["missingContainer", "badContainer", "noRootfile", "missingOPF", "badOPF",
                      "emptySpine", "unknownSpine", "badPercent", "escapeRoot", "archiveRoot"])
    func sampledPackageReportsSpecificFailure(field: String) throws {
        var entries = try EPUBExtractor.unzipEntries(from: sampledArchive())
        let container = "META-INF/container.xml"
        let opf = "OEBPS/content.opf"
        let originalContainer = String(decoding: try #require(entries[container]), as: UTF8.self)
        let originalOPF = String(decoding: try #require(entries[opf]), as: UTF8.self)
        let expected: ExtractionError
        switch field {
        case "missingContainer":
            entries.removeValue(forKey: container)
            expected = .parsingFailed("Missing META-INF/container.xml")
        case "badContainer":
            entries[container] = Data("<container><".utf8)
            expected = .parsingFailed("Could not find OPF path in container.xml")
        case "noRootfile":
            entries[container] = Data(originalContainer.replacingOccurrences(of: "rootfile ", with: "ignored ").utf8)
            expected = .parsingFailed("Could not find OPF path in container.xml")
        case "missingOPF":
            entries.removeValue(forKey: opf)
            expected = .parsingFailed("Could not read OPF file at OEBPS/content.opf")
        case "badOPF":
            entries[opf] = Data("<package><".utf8)
            expected = .parsingFailed("Could not parse OPF file")
        case "emptySpine":
            entries[opf] = Data(originalOPF.replacingOccurrences(of: "itemref", with: "ignored").utf8)
            expected = .parsingFailed("OPF spine contains no chapters")
        case "unknownSpine":
            entries[opf] = Data(originalOPF.replacingOccurrences(of: "idref=\"pg-header\"", with: "idref=\"absent\"").utf8)
            expected = .parsingFailed("Spine item 'absent' is missing from the manifest")
        default:
            let path = field == "badPercent" ? "%ZZ" : field == "escapeRoot" ? "../outside.opf" : "/"
            entries[container] = Data(originalContainer.replacingOccurrences(of: opf, with: path).utf8)
            expected = field == "badPercent"
                ? .parsingFailed("Invalid percent encoding in EPUB path '%ZZ'")
                : field == "escapeRoot"
                    ? .parsingFailed("EPUB path escapes archive root: ../outside.opf")
                    : .parsingFailed("EPUB path resolves to archive root: /")
        }
        let archive = buildStoredZIP(files: entries.sorted { $0.key < $1.key }.map { ($0.key, $0.value) })
        // Exact diagnostics distinguish the intended parser path from an earlier ZIP failure.
        #expect(throws: expected) { try EPUBExtractor().extractText(from: archive) }
    }

    @Test func sampledArchiveWithoutDirectoryPreservesEveryEntry() throws {
        let archive = try sampledArchive()
        let eocd = try #require(archive.range(of: Data([0x50, 0x4b, 0x05, 0x06]), options: .backwards)?.lowerBound)
        let entries = try EPUBExtractor.unzipEntries(from: archive)
        #expect(entries.count == 12)
        #expect(try EPUBExtractor.unzipEntries(from: Data(archive.prefix(littleEndian(archive, at: eocd + 16)))) == entries)
    }

    @Test(arguments: ["ncx", "brokenNCX", "missingNavigation", "missingTarget", "missingFragment", "wholeDocument", "duplicate"])
    func sampledNavigationUsesNCXOrFallsBackWithoutChangingText(mode: String) throws {
        var entries = try EPUBExtractor.unzipEntries(from: sampledArchive())
        let original = try EPUBExtractor().extractText(from: sampledArchive())
        let opf = "OEBPS/content.opf"
        let ncx = "OEBPS/toc.ncx"
        let toc = "OEBPS/toc.xhtml"
        if ["ncx", "brokenNCX"].contains(mode) {
            entries[opf] = Data(String(decoding: try #require(entries[opf]), as: UTF8.self)
                .replacingOccurrences(of: "properties=\"nav\"", with: "properties=\"\"").utf8)
            if mode == "brokenNCX" { entries[ncx] = Data("<ncx><".utf8) }
        } else if mode == "missingNavigation" {
            entries.removeValue(forKey: toc)
        } else {
            let navigation = String(decoding: try #require(entries[toc]), as: UTF8.self)
            let reference = "3578510476723697232_1952-h-0.htm.xhtml#pgepubid00000"
            #expect(navigation.contains(reference))
            let replacement: String
            switch mode {
            case "missingTarget": replacement = "absent.xhtml#pgepubid00000"
            case "missingFragment": replacement = "3578510476723697232_1952-h-0.htm.xhtml#absent"
            case "wholeDocument": replacement = "3578510476723697232_1952-h-0.htm.xhtml"
            default: replacement = reference
            }
            var changed = navigation.replacingOccurrences(of: reference, with: replacement)
            if mode == "duplicate" {
                // Duplicate a sampled list item verbatim, rather than authoring navigation markup.
                let start = try #require(changed.range(of: "<li>"))
                let end = try #require(changed.range(of: "</li>"))
                let item = String(changed[start.lowerBound..<end.upperBound])
                changed.insert(contentsOf: item, at: end.upperBound)
            }
            entries[toc] = Data(changed.utf8)
        }
        let result = try EPUBExtractor().extractText(from: buildStoredZIP(
            files: entries.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }))
        #expect(result.text == original.text)
        #expect(result.text.count == 50_913)
        switch mode {
        case "ncx", "duplicate":
            #expect(result.chapters == original.chapters)
            #expect(result.chapters.map(\.title) == ["The Yellow Wallpaper", "THE FULL PROJECT GUTENBERG™ LICENSE"])
        case "brokenNCX", "missingNavigation":
            #expect(result.chapters.map(\.title) == [
                "The Project Gutenberg eBook of The Yellow Wallpaper", "The Yellow Wallpaper",
                "By Charlotte Perkins Gilman", "THE FULL PROJECT GUTENBERG™ LICENSE"])
        case "missingTarget", "missingFragment":
            #expect(result.chapters == Array(original.chapters.suffix(1)))
        default:
            #expect(result.chapters.first?.startWordIndex == 1)
            #expect(result.chapters.first?.title == "The Yellow Wallpaper")
            #expect(result.chapters.last == original.chapters.last)
        }
    }

    @Test(arguments: [false, true])
    func sampledDuplicateEntryIsRejectedWithAndWithoutDirectory(directory: Bool) throws {
        let entries = try EPUBExtractor.unzipEntries(from: sampledArchive())
        let data = try #require(entries["mimetype"])
        let archive = buildStoredZIP(files: [("mimetype", data), ("mimetype", data)], includeCentralDirectory: directory)
        #expect(throws: ExtractionError.invalidData) { try EPUBExtractor.unzipEntries(from: archive) }
    }

    @Test(arguments: [false, true])
    func corruptDeflateRejectsEmptyAndInvalidCompressedBytes(empty: Bool) throws {
        var archive = try sampledArchive()
        let eocd = try #require(archive.range(of: Data([0x50, 0x4b, 0x05, 0x06]), options: .backwards)?.lowerBound)
        let central = littleEndian(archive, at: eocd + 16)
        // Relabel the sampled stored mimetype as deflate; its bytes are not deflate.
        patch(&archive, at: central + 10, value: 8, width: 2)
        if empty { patch(&archive, at: central + 20, value: 0) }
        #expect(throws: ExtractionError.invalidData) { try EPUBExtractor.unzipEntries(from: archive) }
    }

    @Test("Known-size local records reject a missing or contradictory descriptor",
          arguments: ["missing", "unsigned", "signed"])
    func localHeaderValidatesRequiredDescriptorIntegrity(kind: String) throws {
        var archive = Data(try sampledArchive().prefix(58))
        patch(&archive, at: 6, value: 8, width: 2)
        if kind == "signed" { archive.append(contentsOf: [0x50, 0x4b, 0x07, 0x08]) }
        if kind != "missing" { archive.append(Data(repeating: 0, count: 12)) }
        #expect(throws: ExtractionError.invalidData) { try EPUBExtractor.unzipEntries(from: archive) }
    }

    @Test(arguments: [false, true])
    func sampledLocalRecordAcceptsValidDescriptorAndRejectsEachCorruptField(signed: Bool) throws {
        let sample = try sampledArchive()
        var archive = Data(sample.prefix(58))
        patch(&archive, at: 6, value: 8, width: 2)
        if signed { archive.append(contentsOf: [0x50, 0x4b, 0x07, 0x08]) }
        let fieldsStart = archive.count
        archive.append(sample[14..<26])
        let expected = try EPUBExtractor.unzipEntries(from: Data(sample.prefix(58)))
        #expect(try EPUBExtractor.unzipEntries(from: archive) == expected)
        for field in [0, 4, 8] {
            var corrupt = archive
            corrupt[fieldsStart + field] ^= 1
            #expect(throws: ExtractionError.invalidData) { try EPUBExtractor.unzipEntries(from: corrupt) }
        }
        for removed in 1...12 {
            #expect(throws: ExtractionError.invalidData) {
                try EPUBExtractor.unzipEntries(from: Data(archive.dropLast(removed)))
            }
        }
    }

    @Test(arguments: ["TheYellowWallpaper", "AChristmasCarol", "TheMetamorphosis"])
    func realSampleBooksStillExtractWithAndWithoutDirectory(name: String) throws {
        let url = try #require(Bundle.main.url(forResource: name, withExtension: "epub"))
        let archive = try Data(contentsOf: url)
        let eocd = try #require(archive.range(of: Data([0x50, 0x4b, 0x05, 0x06]), options: .backwards)?.lowerBound)
        let localOnly = Data(archive.prefix(littleEndian(archive, at: eocd + 16)))
        let original = try EPUBExtractor().extractText(from: archive)
        let recovered = try EPUBExtractor().extractText(from: localOnly)
        #expect(!original.text.isEmpty)
        #expect(recovered.text == original.text)
        #expect(recovered.chapters == original.chapters)
        #expect(try EPUBExtractor.unzipEntries(from: localOnly) == EPUBExtractor.unzipEntries(from: archive))
    }

    private func sampledArchive() throws -> Data {
        let url = try #require(Bundle.main.url(forResource: "TheYellowWallpaper", withExtension: "epub"))
        return try Data(contentsOf: url)
    }

    private func littleEndian(_ data: Data, at offset: Int) -> Int {
        (0..<4).reduce(0) { $0 | (Int(data[offset + $1]) << (8 * $1)) }
    }

    private func patch(_ data: inout Data, at offset: Int, value: UInt32, width: Int = 4) {
        for byte in 0..<width { data[offset + byte] = UInt8(truncatingIfNeeded: value >> (8 * byte)) }
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
