import Foundation

nonisolated enum OPDSBrowseLogic {
    struct EntrySections: Equatable {
        let navigation: [OPDSEntry]
        let books: [OPDSEntry]
    }

    enum SearchAction: Equatable {
        case clear
        case unavailable
        case fetch(URL)
    }

    static func displayEntries(
        searchText: String,
        searchedFeed: OPDSFeed?,
        paginatedEntries: [OPDSEntry]
    ) -> [OPDSEntry] {
        if !searchText.isEmpty, let searchedFeed {
            return searchedFeed.entries
        }
        return paginatedEntries
    }

    static func sections(for entries: [OPDSEntry]) -> EntrySections {
        EntrySections(
            navigation: entries.filter {
                $0.acquisitions.isEmpty && $0.navigationLink != nil
            },
            books: entries.filter { !$0.acquisitions.isEmpty }
        )
    }

    static func searchAction(
        query: String,
        advertisedTemplate: String?,
        baseURL: URL?
    ) -> SearchAction {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return .clear }
        guard let template = advertisedTemplate ?? defaultSearchTemplate(baseURL: baseURL) else {
            return .unavailable
        }
        let resolved = template.replacingOccurrences(
            of: "{searchTerms}",
            with: query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? query
        )
        guard let url = URL(string: resolved) else { return .unavailable }
        return .fetch(url)
    }

    private static func defaultSearchTemplate(baseURL: URL?) -> String? {
        guard let baseURL else { return nil }
        return baseURL.absoluteString
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            + "/search/{searchTerms}"
    }
}
