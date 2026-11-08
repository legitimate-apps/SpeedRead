import Foundation

/// Highlights and bookmarks pushed for one book. Each is addressed by its words (a text quote),
/// never a reader-specific locator; the server resolves the quote against its copy of the book
/// for every other reader. Deletes are named, never inferred from absence.
nonisolated struct KOSyncAnnotationPush: Encodable, Equatable, Sendable {
    let document: String
    let device: String
    let deviceID: String
    let annotations: [Row]
    let deleted: [String]

    static let source = "textquote"

    struct Row: Encodable, Equatable, Sendable {
        let annotationID: String
        let type: KOSyncAnnotationType
        let quote: TextQuote
        let percentage: Double
        let note: String?
        let deviceOriginID: String

        enum CodingKeys: String, CodingKey {
            case annotationID = "annotation_id", source, type, quote = "text_quote", percentage
            case note = "note_text", color, deviceOriginID = "device_origin_id", hidden
        }

        /// `note_text` is always sent, `null` included: a note removed here must be removed there.
        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(annotationID, forKey: .annotationID)
            try container.encode(KOSyncAnnotationPush.source, forKey: .source)
            try container.encode(type.rawValue, forKey: .type)
            try container.encode(quote, forKey: .quote)
            try container.encode(percentage, forKey: .percentage)
            try container.encode(note, forKey: .note)
            // SpeedRead has one highlight colour; the server stores colours by name.
            try container.encode("yellow", forKey: .color)
            try container.encode(deviceOriginID, forKey: .deviceOriginID)
            try container.encode(false, forKey: .hidden)
        }
    }

    enum CodingKeys: String, CodingKey {
        case document, device, deviceID = "device_id", annotations, deleted
        case deleteSource = "delete_source"
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(document, forKey: .document)
        try container.encode(device, forKey: .device)
        try container.encode(deviceID, forKey: .deviceID)
        try container.encode(annotations, forKey: .annotations)
        try container.encode(deleted, forKey: .deleted)
        try container.encode(Self.source, forKey: .deleteSource)
    }
}

/// The server's annotation vocabulary. A bookmark is a "dogear": a point, one word long.
nonisolated enum KOSyncAnnotationType: String, Sendable {
    case highlight
    case dogear
    case note
}

/// One annotation the server holds for a book, from whichever reader made it. Hidden rows are
/// deletions, kept so every reader can mirror them.
nonisolated struct KOSyncRemoteAnnotation: Equatable, Sendable {
    let annotationID: String
    let source: String?
    let type: KOSyncAnnotationType?
    let quote: TextQuote?
    let note: String?
    let hidden: Bool
    let deviceOriginID: String?
    /// 0–1, when the server sends one: it places a quote that occurs more than once.
    let percentage: Double?

    /// Whether this device may change the row on the server: `AnnotationSyncLogic.isOwned`.
    func isOwned(by deviceID: String) -> Bool {
        AnnotationSyncLogic.isOwned(source: source, originDevice: deviceOriginID, deviceID: deviceID)
    }
}

/// What the server made of a push.
nonisolated struct KOSyncAnnotationPushResult: Equatable, Sendable {
    /// False when the server does not have this book.
    let matched: Bool
    let unresolved: [String]
}

nonisolated extension KOSyncWire {
    static let textQuoteAnnotationsCapability = "annotations_text_quote"

    static func annotationsPushURL(base: URL) -> URL {
        base.appendingPathComponent("syncs").appendingPathComponent("annotations")
    }

    /// `text_quote=1` asks the server to derive a quote for other readers' rows; without it only
    /// rows this app pushed carry one.
    static func annotationsFetchURL(base: URL, document: String) -> URL {
        var components = URLComponents(url: annotationsPushURL(base: base).appendingPathComponent(document),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "text_quote", value: "1")]
        return components.url!
    }

    static func encode(_ push: KOSyncAnnotationPush) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(push)
    }

    /// The rows a server holds for a book, or nil when it does not know the book. A row this
    /// client cannot read is skipped rather than failing the whole book.
    static func decodeAnnotations(_ data: Data) throws -> [KOSyncRemoteAnnotation]? {
        struct Body: Decodable {
            let annotations: [Lenient]?
            let book_known: Bool?
            let matched: Bool?
        }
        struct Lenient: Decodable {
            let row: KOSyncRemoteAnnotation?
            init(from decoder: any Decoder) throws { row = try? Row(from: decoder).annotation }
        }
        let body = try JSONDecoder().decode(Body.self, from: data)
        if body.book_known == false || body.matched == false { return nil }
        return (body.annotations ?? []).compactMap(\.row)
    }

    static func decodeAnnotationPushResult(_ data: Data) -> KOSyncAnnotationPushResult {
        struct Body: Decodable {
            let matched: Bool?
            let unresolved: [String]?
        }
        let body = try? JSONDecoder().decode(Body.self, from: data)
        return KOSyncAnnotationPushResult(matched: body?.matched ?? true, unresolved: body?.unresolved ?? [])
    }

    private struct Row: Decodable {
        let annotation: KOSyncRemoteAnnotation

        enum CodingKeys: String, CodingKey {
            case annotation_id, source, type, text_quote, note_text, hidden, device_origin_id, percentage
        }

        init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let id: String = if let text = try? c.decode(String.self, forKey: .annotation_id) {
                text
            } else {
                String(try c.decode(Int.self, forKey: .annotation_id))
            }
            guard !id.isEmpty else {
                throw DecodingError.dataCorruptedError(forKey: .annotation_id, in: c, debugDescription: "empty id")
            }
            let note = try? c.decodeIfPresent(String.self, forKey: .note_text)
            let percentage = (try? c.decodeIfPresent(Double.self, forKey: .percentage)).flatMap { $0 }
            annotation = KOSyncRemoteAnnotation(
                annotationID: id,
                source: try? c.decodeIfPresent(String.self, forKey: .source),
                type: (try? c.decodeIfPresent(String.self, forKey: .type)).flatMap { $0 }
                    .flatMap(KOSyncAnnotationType.init(rawValue:)),
                quote: (try? c.decodeIfPresent(TextQuote.self, forKey: .text_quote)).flatMap { $0 },
                note: note.flatMap { $0.isEmpty ? nil : $0 },
                hidden: (try? c.decodeIfPresent(Bool.self, forKey: .hidden)).flatMap { $0 } ?? false,
                deviceOriginID: (try? c.decodeIfPresent(String.self, forKey: .device_origin_id)).flatMap { $0 },
                percentage: percentage.map { min(max($0 > 1 ? $0 / 100 : $0, 0), 1) }
            )
        }
    }
}

extension KOSyncClient {
    /// Nil when the server does not know the book.
    func annotations(of document: String, on server: OPDSRequestConfiguration) async throws -> [KOSyncRemoteAnnotation]? {
        guard let base = KOSyncWire.kosyncBase(fromOPDS: server.baseURL) else { throw OPDSError.invalidURL }
        let (data, status) = try await send(KOSyncWire.annotationsFetchURL(base: base, document: document),
                                            method: "GET", server: server)
        guard (200...299).contains(status) else { throw OPDSError.httpError(status: status) }
        do {
            return try KOSyncWire.decodeAnnotations(data)
        } catch {
            throw OPDSError.parseError
        }
    }

    func push(_ annotations: KOSyncAnnotationPush, to server: OPDSRequestConfiguration) async throws -> KOSyncAnnotationPushResult {
        guard let base = KOSyncWire.kosyncBase(fromOPDS: server.baseURL) else { throw OPDSError.invalidURL }
        let (data, status) = try await send(KOSyncWire.annotationsPushURL(base: base), method: "PUT", server: server,
                                            body: try KOSyncWire.encode(annotations))
        guard (200...299).contains(status) else { throw OPDSError.httpError(status: status) }
        return KOSyncWire.decodeAnnotationPushResult(data)
    }
}
