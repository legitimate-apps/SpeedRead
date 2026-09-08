import Foundation

/// Preserve every download while distinguishing variants with the metadata the server provides.
nonisolated enum OPDSAcquisitionLabelLogic {
    static func labels(for acquisitions: [OPDSAcquisition]) -> [String] {
        let names = acquisitions.map { acquisition in
            let title = acquisition.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return title.isEmpty ? acquisition.displayFormat : "\(acquisition.displayFormat) · \(title)"
        }
        let nameCounts = Dictionary(grouping: names, by: { $0 }).mapValues(\.count)
        let sized = zip(acquisitions, names).map { acquisition, name in
            guard nameCounts[name, default: 0] > 1, let length = acquisition.length, length > 0 else {
                return name
            }
            return "\(name) · \(ByteCountFormatter.string(fromByteCount: Int64(length), countStyle: .file))"
        }
        let sizedCounts = Dictionary(grouping: sized, by: { $0 }).mapValues(\.count)
        return sized.enumerated().map { index, label in
            sizedCounts[label, default: 0] > 1 ? "\(label) (\(index + 1))" : label
        }
    }
}
