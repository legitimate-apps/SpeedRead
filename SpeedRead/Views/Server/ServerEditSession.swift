import Foundation
import SwiftData
import Observation

@Observable
@MainActor
final class ServerEditSession {
    var name: String = ""
    var urlString: String = ""
    var username: String = ""
    var password: String = ""
    var allowInsecureHTTP: Bool = false
    var syncsReadingPosition: Bool = true

    private(set) var testState: ServerEditLogic.ConnectionState = .idle
    private(set) var validationError: String?

    var canSave: Bool {
        OPDSServerFormLogic.canSave(name: name, urlString: urlString)
    }

    func loadExisting(server: OPDSServer?) {
        let values = ServerEditLogic.initialValues(server: server)
        name = values.name
        urlString = values.urlString
        username = values.username
        password = values.password
        allowInsecureHTTP = values.allowInsecureHTTP
        syncsReadingPosition = server?.syncsReadingPosition ?? true
    }

    func save(server: OPDSServer?, modelContext: ModelContext,
              positionSync: ServerPositionSync = .shared) -> Bool {
        let validated: ServerEditLogic.ValidatedServer
        switch ServerEditLogic.saveDecision(
            name: name,
            urlString: urlString,
            username: username,
            password: password,
            allowInsecureHTTP: allowInsecureHTTP
        ) {
        case .failure(let message):
            validationError = message
            return false
        case .valid(let value):
            validated = value
        }
        validationError = nil

        if let server {
            server.name = validated.name
            server.baseURLString = validated.url.absoluteString
            server.username = validated.username
            server.allowInsecureHTTP = validated.allowInsecureHTTP
            server.syncsReadingPosition = syncsReadingPosition
            persistPassword(validated.password, for: server.keychainTag)
            positionSync.serverSettingsChanged(server)
            ServerAnnotationSync.shared.serverSettingsChanged(server)
        } else {
            let s = OPDSServer(
                name: validated.name,
                baseURL: validated.url,
                username: validated.username,
                allowInsecureHTTP: validated.allowInsecureHTTP,
                sortIndex: ServerEditLogic.sortIndex()
            )
            s.syncsReadingPosition = syncsReadingPosition
            modelContext.insert(s)
            persistPassword(validated.password, for: s.keychainTag)
        }
        try? modelContext.save()
        return true
    }

    private func persistPassword(_ password: String, for tag: String) {
        switch ServerEditLogic.passwordAction(password: password) {
        case .delete:
            try? KeychainStore.deletePassword(for: tag)
        case .set(let value):
            try? KeychainStore.setPassword(value, for: tag)
        }
    }

    func testConnection(server: OPDSServer?, makeClient: () -> OPDSClient) async {
        let url: URL
        switch ServerEditLogic.connectionDecision(
            urlString: urlString,
            allowInsecureHTTP: allowInsecureHTTP
        ) {
        case .probe(let validatedURL):
            url = validatedURL
        case .failure(let message):
            testState = .failure(message)
            return
        }
        testState = .running
        let tag = ServerEditLogic.connectionTag(existingTag: server?.keychainTag)
        if !password.isEmpty {
            try? KeychainStore.setPassword(password, for: tag.value)
        }
        defer {
            if tag.deletesAfterProbe {
                try? KeychainStore.deletePassword(for: tag.value)
            }
        }

        let identity = OPDSServerFormLogic.normalizedIdentity(
            name: name,
            username: username,
            password: password
        )
        let probeServer = OPDSServer(
            name: "probe",
            baseURL: url,
            username: identity.username,
            allowInsecureHTTP: allowInsecureHTTP
        )
        probeServer.keychainTag = tag.value

        let client = makeClient()
        do {
            _ = try await client.testConnection(OPDSRequestConfiguration(probeServer))
            testState = .success
        } catch let opdsError as OPDSError {
            testState = .failure(opdsError.errorDescription ?? "Unknown error")
        } catch {
            testState = .failure(error.localizedDescription)
        }
    }
}
