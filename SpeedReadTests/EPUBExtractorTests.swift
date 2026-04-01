import Testing
import Foundation
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

    /// Builds a minimal ZIP archive using stored (no compression) method.
    private func buildStoredZIP(files: [(name: String, data: Data)]) -> Data {
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
