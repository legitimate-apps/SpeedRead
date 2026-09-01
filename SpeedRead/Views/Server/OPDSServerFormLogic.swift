import Foundation

nonisolated enum OPDSServerFormLogic {
    enum URLValidation: Equatable {
        case valid(URL)
        case invalid
        case insecureHTTP
    }

    struct Identity: Equatable {
        let name: String
        let username: String
        let password: String
    }

    static func canSave(name: String, urlString: String) -> Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !urlString.trimmingCharacters(in: .whitespaces).isEmpty
    }

    static func isPendingPlainHTTP(_ urlString: String) -> Bool {
        urlString.lowercased().hasPrefix("http://")
    }

    static func validateURL(
        _ urlString: String,
        allowInsecureHTTP: Bool
    ) -> URLValidation {
        var value = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if let separator = value.range(of: "://") {
            let explicitScheme = value[..<separator.lowerBound].lowercased()
            guard explicitScheme == "http" || explicitScheme == "https" else {
                return .invalid
            }
        } else {
            value = "https://" + value
        }
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            return .invalid
        }
        if scheme == "http" && !allowInsecureHTTP {
            return .insecureHTTP
        }
        return .valid(url)
    }

    static func normalizedIdentity(
        name: String,
        username: String,
        password: String
    ) -> Identity {
        Identity(
            name: name.trimmingCharacters(in: .whitespaces),
            username: username.trimmingCharacters(in: .whitespaces),
            password: password
        )
    }
}
