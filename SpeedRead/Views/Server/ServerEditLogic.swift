//  ServerEditLogic.swift
//  Pure decisions behind ServerEditView.swift. In its OWN file deliberately, not by style preference.
//
//  Attributable coverage is measured per FILE. A tested type sharing a file with SwiftUI
//  body markup pulls every one of those untested lines into the denominator, so the
//  metric reports worse the more logic you extract -- which is exactly backwards.
//  MEASURED 2026-09-01 with this type inline: ServerEditView.swift read 73/481 (15.18%), contributing
//  481 lines to 'attributable'. The two logic types that already lived in their own
//  files read 97.50% and 100.00%. Same tests, same code, different file boundary.
import Foundation
import SwiftData

struct ServerEditLogic {
    struct FormValues: Equatable {
        let name: String
        let urlString: String
        let username: String
        let password: String
        let allowInsecureHTTP: Bool

        static let empty = FormValues(
            name: "",
            urlString: "",
            username: "",
            password: "",
            allowInsecureHTTP: false
        )
    }

    struct Presentation: Equatable {
        let navigationTitle: String
        let showsCancel: Bool
    }

    enum ConnectionState: Equatable {
        case idle
        case running
        case success
        case failure(String)
    }

    struct ValidatedServer: Equatable {
        let url: URL
        let name: String
        let username: String
        let password: String
        let allowInsecureHTTP: Bool
    }

    enum SaveDecision: Equatable {
        case valid(ValidatedServer)
        case failure(String)
    }

    enum ConnectionDecision: Equatable {
        case probe(URL)
        case failure(String)
    }

    enum PasswordAction: Equatable {
        case delete
        case set(String)
    }

    struct ConnectionTag: Equatable {
        let value: String
        let deletesAfterProbe: Bool
    }

    static func initialValues(
        server: OPDSServer?,
        passwordForTag: (String) -> String? = KeychainStore.password(for:)
    ) -> FormValues {
        guard let server else { return .empty }
        return FormValues(
            name: server.name,
            urlString: server.baseURLString,
            username: server.username,
            password: passwordForTag(server.keychainTag) ?? "",
            allowInsecureHTTP: server.allowInsecureHTTP
        )
    }

    static func presentation(server: OPDSServer?) -> Presentation {
        guard let server else {
            return Presentation(navigationTitle: "New Server", showsCancel: false)
        }
        return Presentation(navigationTitle: server.name, showsCancel: true)
    }

    static func canTestConnection(
        state: ConnectionState,
        urlString: String
    ) -> Bool {
        state != .running
            && !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func saveDecision(
        name: String,
        urlString: String,
        username: String,
        password: String,
        allowInsecureHTTP: Bool
    ) -> SaveDecision {
        let url: URL
        switch OPDSServerFormLogic.validateURL(
            urlString,
            allowInsecureHTTP: allowInsecureHTTP
        ) {
        case .valid(let validatedURL):
            url = validatedURL
        case .invalid:
            return .failure("Please enter a valid URL beginning with http:// or https://.")
        case .insecureHTTP:
            return .failure("This URL uses http://. Enable “Allow plain HTTP” or switch to https://.")
        }
        let identity = OPDSServerFormLogic.normalizedIdentity(
            name: name,
            username: username,
            password: password
        )
        return .valid(.init(
            url: url,
            name: identity.name,
            username: identity.username,
            password: identity.password,
            allowInsecureHTTP: allowInsecureHTTP
        ))
    }

    static func connectionDecision(
        urlString: String,
        allowInsecureHTTP: Bool
    ) -> ConnectionDecision {
        switch OPDSServerFormLogic.validateURL(
            urlString,
            allowInsecureHTTP: allowInsecureHTTP
        ) {
        case .valid(let url):
            return .probe(url)
        case .invalid:
            return .failure("Invalid URL")
        case .insecureHTTP:
            return .failure("Plain HTTP is disabled for this server")
        }
    }

    static func passwordAction(password: String) -> PasswordAction {
        password.isEmpty ? .delete : .set(password)
    }

    static func sortIndex(now: Date = Date()) -> Int {
        Int(now.timeIntervalSince1970)
    }

    static func connectionTag(
        existingTag: String?,
        generatedTag: String = UUID().uuidString
    ) -> ConnectionTag {
        if let existingTag {
            return ConnectionTag(value: existingTag, deletesAfterProbe: false)
        }
        return ConnectionTag(value: generatedTag, deletesAfterProbe: true)
    }
}
