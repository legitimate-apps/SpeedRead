//  OPDSAtomParser.swift
import Foundation

nonisolated struct OPDSFeed: Equatable, Sendable {
    let title: String
    let id: String
    let updated: Date?
    let entries: [OPDSEntry]
    let navigationLinks: [OPDSLink]
    let nextPageURL: URL?
    let searchDescriptionURL: URL?
    /// OpenSearch-style URL template with `{searchTerms}` placeholder.
    /// Kept as a String (not URL) so the placeholder braces survive
    /// without being percent-encoded by URL normalization.
    let searchTemplate: String?
}

nonisolated struct OPDSEntry: Equatable, Identifiable, Sendable {
    let id: String
    let title: String
    let authors: [String]
    let summary: String?
    let updated: Date?
    let published: Date?
    let language: String?
    let coverURL: URL?
    let thumbnailURL: URL?
    let navigationLink: URL?
    let acquisitions: [OPDSAcquisition]
}

nonisolated struct OPDSAcquisition: Equatable, Sendable {
    let url: URL
    let mimeType: String
    let length: Int?
    let title: String?

    var displayFormat: String {
        switch mimeType {
        case "application/epub+zip": return "EPUB"
        case "application/pdf": return "PDF"
        case "text/plain": return "TXT"
        case "application/x-mobipocket-ebook": return "MOBI"
        case "application/vnd.amazon.ebook": return "AZW"
        case "application/rtf", "text/rtf": return "RTF"
        case "text/html": return "HTML"
        default:
            if let slash = mimeType.lastIndex(of: "/") {
                return mimeType[mimeType.index(after: slash)...].uppercased()
            }
            return mimeType.uppercased()
        }
    }
}

nonisolated struct OPDSLink: Equatable, Sendable {
    let rel: String
    let href: String
    let type: String?
    let title: String?
}

nonisolated enum OPDSParseError: Error {
    case parserFailed(Error?)
    case invalidRootElement
}

/// Streaming OPDS 1.x Atom parser. Builds an `OPDSFeed` from the bytes of an
/// Atom catalog response. Relative `href` attributes are resolved against the
/// provided `baseURL`.
nonisolated final class OPDSAtomParser: NSObject {
    private let baseURL: URL

    private var feedTitle: String = ""
    private var feedID: String = ""
    private var feedUpdated: Date?
    private var entries: [OPDSEntry] = []
    private var navigationLinks: [OPDSLink] = []
    private var nextPageURL: URL?
    private var searchDescriptionURL: URL?

    private var searchTemplateString: String?

    private var inEntry: Bool = false
    private var elementStack: [String] = []
    private var inAuthor: Bool = false
    private var characterBuffer: String = ""

    private var currentEntryTitle: String = ""
    private var currentEntryID: String = ""
    private var currentEntryAuthors: [String] = []
    private var currentEntrySummary: String?
    private var currentEntryUpdated: Date?
    private var currentEntryPublished: Date?
    private var currentEntryLanguage: String?
    private var currentEntryCover: URL?
    private var currentEntryThumbnail: URL?
    private var currentEntryNavigationLink: URL?
    private var currentEntryAcquisitions: [OPDSAcquisition] = []

    init(baseURL: URL) {
        self.baseURL = baseURL
    }

    func parse(data: Data) throws -> OPDSFeed {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldProcessNamespaces = false
        guard parser.parse() else {
            throw OPDSParseError.parserFailed(parser.parserError)
        }
        return OPDSFeed(
            title: feedTitle,
            id: feedID,
            updated: feedUpdated,
            entries: entries,
            navigationLinks: navigationLinks,
            nextPageURL: nextPageURL,
            searchDescriptionURL: searchDescriptionURL,
            searchTemplate: searchTemplateString
        )
    }

    static func parseDate(_ string: String) -> Date? {
        // Formatters are mutable and non-Sendable. Each call owns its formatter, so
        // concurrent feed parses never share it; retain the same options and fallback.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    private func resolveURL(_ href: String) -> URL? {
        if let absolute = URL(string: href), absolute.scheme != nil {
            return absolute
        }
        return URL(string: href, relativeTo: baseURL)?.absoluteURL
    }

    private func handleLinkAttributes(_ attrs: [String: String]) {
        guard let href = attrs["href"] else { return }
        let rel = attrs["rel"] ?? ""
        let type = attrs["type"]
        let title = attrs["title"]

        if inEntry {
            switch rel {
            case "http://opds-spec.org/image":
                currentEntryCover = resolveURL(href)
            case "http://opds-spec.org/image/thumbnail":
                currentEntryThumbnail = resolveURL(href)
            case "http://opds-spec.org/acquisition",
                 "http://opds-spec.org/acquisition/open-access":
                if let url = resolveURL(href) {
                    let length = attrs["length"].flatMap { Int($0) }
                    let mime = type ?? "application/octet-stream"
                    currentEntryAcquisitions.append(
                        OPDSAcquisition(url: url, mimeType: mime, length: length, title: title)
                    )
                }
            default:
                if rel.isEmpty || rel == "subsection" || rel == "alternate" {
                    if let url = resolveURL(href) {
                        currentEntryNavigationLink = url
                    }
                }
            }
        } else {
            switch rel {
            case "next":
                nextPageURL = resolveURL(href)
            case "search":
                if type == "application/opensearchdescription+xml" {
                    searchDescriptionURL = resolveURL(href)
                } else if href.contains("{searchTerms}") {
                    if let absolute = URL(string: href), absolute.scheme != nil {
                        searchTemplateString = absolute.absoluteString
                    } else {
                        searchTemplateString = URL(string: "/", relativeTo: baseURL)
                            .map { $0.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + href }
                    }
                }
            default:
                if let url = resolveURL(href) {
                    navigationLinks.append(
                        OPDSLink(rel: rel, href: url.absoluteString, type: type, title: title)
                    )
                }
            }
        }
    }
}

nonisolated extension OPDSAtomParser: XMLParserDelegate {
    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attrs: [String: String] = [:]
    ) {
        let localName = elementName.localOPDSName

        switch localName {
        case "entry":
            inEntry = true
            currentEntryTitle = ""
            currentEntryID = ""
            currentEntryAuthors = []
            currentEntrySummary = nil
            currentEntryUpdated = nil
            currentEntryPublished = nil
            currentEntryLanguage = nil
            currentEntryCover = nil
            currentEntryThumbnail = nil
            currentEntryNavigationLink = nil
            currentEntryAcquisitions = []
        case "author":
            inAuthor = true
        case "link":
            handleLinkAttributes(attrs)
        default:
            break
        }

        elementStack.append(localName)
        characterBuffer = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        characterBuffer += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let localName = elementName.localOPDSName
        let trimmed = characterBuffer.trimmingCharacters(in: .whitespacesAndNewlines)

        if inEntry {
            switch localName {
            case "title":
                if currentEntryTitle.isEmpty { currentEntryTitle = trimmed }
            case "id":
                currentEntryID = trimmed
            case "summary", "content":
                if currentEntrySummary == nil { currentEntrySummary = trimmed }
            case "updated":
                currentEntryUpdated = OPDSAtomParser.parseDate(trimmed)
            case "published":
                currentEntryPublished = OPDSAtomParser.parseDate(trimmed)
            case "language":
                currentEntryLanguage = trimmed.isEmpty ? nil : trimmed
            case "name" where inAuthor:
                if !trimmed.isEmpty { currentEntryAuthors.append(trimmed) }
            case "author":
                inAuthor = false
            case "entry":
                let entry = OPDSEntry(
                    id: currentEntryID,
                    title: currentEntryTitle,
                    authors: currentEntryAuthors,
                    summary: currentEntrySummary,
                    updated: currentEntryUpdated,
                    published: currentEntryPublished,
                    language: currentEntryLanguage,
                    coverURL: currentEntryCover,
                    thumbnailURL: currentEntryThumbnail,
                    navigationLink: currentEntryNavigationLink,
                    acquisitions: currentEntryAcquisitions
                )
                entries.append(entry)
                inEntry = false
            default:
                break
            }
        } else {
            switch localName {
            case "title":
                if feedTitle.isEmpty { feedTitle = trimmed }
            case "id":
                if feedID.isEmpty { feedID = trimmed }
            case "updated":
                if feedUpdated == nil { feedUpdated = OPDSAtomParser.parseDate(trimmed) }
            default:
                break
            }
        }

        characterBuffer = ""
        if !elementStack.isEmpty { elementStack.removeLast() }
    }
}

nonisolated private extension String {
    /// Strip a namespace prefix and return the local element name lowercased
    /// for case-insensitive matching against Atom/OPDS element names.
    var localOPDSName: String {
        if let colon = lastIndex(of: ":") {
            return String(self[index(after: colon)...]).lowercased()
        }
        return lowercased()
    }
}
