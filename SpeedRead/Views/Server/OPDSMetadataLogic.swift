import Foundation

/// Shared by catalogue rows and book details; never infers metadata or catalogue routes.
nonisolated enum OPDSMetadataLogic {
    struct Field: Equatable, Identifiable {
        let label: String
        let value: String
        var id: String { label }
        var text: String { "\(label): \(value)" }
    }

    static func discoveryFields(for entry: OPDSEntry) -> [Field] {
        var fields: [Field] = []
        let categories = entry.categories.map(\.displayName).filter { !$0.isEmpty }
        if !categories.isEmpty {
            fields.append(Field(label: "Categories", value: categories.joined(separator: ", ")))
        }
        if let publisher = entry.publisher, !publisher.isEmpty {
            fields.append(Field(label: "Publisher", value: publisher))
        }
        return fields
    }

    static func detailFields(for entry: OPDSEntry) -> [Field] {
        var fields = discoveryFields(for: entry)
        if let language = entry.language, !language.isEmpty {
            fields.append(Field(label: "Language", value: language.uppercased()))
        }
        return fields
    }
}
