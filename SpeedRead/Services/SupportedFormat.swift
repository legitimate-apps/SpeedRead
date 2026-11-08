import Foundation

nonisolated enum SupportedFormat: CaseIterable, Sendable {
    case epub
    case pdf
    case plainText
    case richText

    var fileExtension: String {
        fileExtensions[0]
    }

    var mimeTypes: [String] {
        switch self {
        case .epub:
            return ["application/epub+zip"]
        case .pdf:
            return ["application/pdf"]
        case .plainText:
            return ["text/plain"]
        case .richText:
            return ["application/rtf", "text/rtf"]
        }
    }

    init?(fileExtension: String) {
        let normalizedExtension = fileExtension.lowercased()
        guard let format = Self.allCases.first(where: {
            $0.fileExtensions.contains(normalizedExtension)
        }) else {
            return nil
        }
        self = format
    }

    init?(mimeType: String) {
        guard let format = Self.allCases.first(where: {
            $0.mimeTypes.contains(mimeType)
        }) else {
            return nil
        }
        self = format
    }

    private var fileExtensions: [String] {
        switch self {
        case .epub:
            return ["epub"]
        case .pdf:
            return ["pdf"]
        case .plainText:
            return ["txt", "text"]
        case .richText:
            return ["rtf"]
        }
    }
}
