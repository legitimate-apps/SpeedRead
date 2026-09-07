import Foundation
import Testing
@testable import SpeedRead

@Suite("Server edit view decisions")
@MainActor
struct ServerEditLogicTests {
    @Test func initialValuesAreEmptyForNewAndLoadEveryStoredFieldForEdit() {
        let server = makeServer()
        server.keychainTag = "known-tag"

        #expect(ServerEditLogic.initialValues(
            server: nil,
            passwordForTag: { _ in "must not be used" }
        ) == .empty)
        #expect(ServerEditLogic.initialValues(
            server: server,
            passwordForTag: { tag in tag == "known-tag" ? "secret" : nil }
        ) == .init(
            name: "Library",
            urlString: "http://books.example/opds",
            username: "reader",
            password: "secret",
            allowInsecureHTTP: true
        ))
    }

    @Test func initialValuesDefaultReadsTheProductionCredentialStore() throws {
        let server = makeServer()
        server.keychainTag = "server-edit-test-\(UUID().uuidString)"
        try KeychainStore.setPassword("stored-secret", for: server.keychainTag)
        defer { try? KeychainStore.deletePassword(for: server.keychainTag) }

        #expect(ServerEditLogic.initialValues(server: server).password == "stored-secret")
    }

    @Test func presentationDistinguishesNewFromEditing() {
        #expect(ServerEditLogic.presentation(server: nil) == .init(
            navigationTitle: "New Server",
            showsCancel: false
        ))
        #expect(ServerEditLogic.presentation(server: makeServer()) == .init(
            navigationTitle: "Library",
            showsCancel: true
        ))
    }

    @Test func connectionEnablementRequiresAURLAndAnIdleState() {
        #expect(!ServerEditLogic.canTestConnection(state: .idle, urlString: " \n "))
        #expect(ServerEditLogic.canTestConnection(state: .idle, urlString: "books.example"))
        #expect(!ServerEditLogic.canTestConnection(state: .running, urlString: "books.example"))
        #expect(ServerEditLogic.canTestConnection(state: .success, urlString: "books.example"))
        #expect(ServerEditLogic.canTestConnection(state: .failure("Offline"), urlString: "books.example"))
    }

    @Test func saveDecisionOwnsValidationMessagesAndNormalizedFields() {
        #expect(ServerEditLogic.saveDecision(
            name: "Library",
            urlString: "https://",
            username: "reader",
            password: "secret",
            allowInsecureHTTP: false
        ) == .failure("Please enter a valid URL beginning with http:// or https://."))
        #expect(ServerEditLogic.saveDecision(
            name: "Library",
            urlString: "http://books.example/opds",
            username: "reader",
            password: "secret",
            allowInsecureHTTP: false
        ) == .failure("This URL uses http://. Enable “Allow plain HTTP” or switch to https://."))
        #expect(ServerEditLogic.saveDecision(
            name: " Home Library ",
            urlString: " books.example/opds ",
            username: " reader ",
            password: " secret with spaces ",
            allowInsecureHTTP: false
        ) == .valid(.init(
            url: URL(string: "https://books.example/opds")!,
            name: "Home Library",
            username: "reader",
            password: " secret with spaces ",
            allowInsecureHTTP: false
        )))
    }

    @Test func connectionDecisionUsesConnectionSpecificValidationMessages() {
        #expect(ServerEditLogic.connectionDecision(
            urlString: "https://",
            allowInsecureHTTP: false
        ) == .failure("Invalid URL"))
        #expect(ServerEditLogic.connectionDecision(
            urlString: "ftp://books.example/opds",
            allowInsecureHTTP: true
        ) == .failure("Invalid URL"))
        #expect(ServerEditLogic.connectionDecision(
            urlString: "http://books.example/opds",
            allowInsecureHTTP: false
        ) == .failure("Plain HTTP is disabled for this server"))
        #expect(ServerEditLogic.connectionDecision(
            urlString: "books.example/opds",
            allowInsecureHTTP: false
        ) == .probe(URL(string: "https://books.example/opds")!))
    }

    @Test func passwordPersistenceDeletesEmptyValuesAndSetsNonemptyValues() {
        #expect(ServerEditLogic.passwordAction(password: "") == .delete)
        #expect(ServerEditLogic.passwordAction(password: "secret") == .set("secret"))
    }

    @Test func sortIndexUsesInjectedTimeAndTheProductionClockDefault() {
        #expect(ServerEditLogic.sortIndex(
            now: Date(timeIntervalSince1970: 1234.9)
        ) == 1234)

        let lowerBound = Int(Date().timeIntervalSince1970)
        let actual = ServerEditLogic.sortIndex()
        let upperBound = Int(Date().timeIntervalSince1970)
        #expect((lowerBound...upperBound).contains(actual))
    }

    @Test func connectionTagReusesStoredTagsAndMarksGeneratedTagsForCleanup() {
        #expect(ServerEditLogic.connectionTag(
            existingTag: "stored",
            generatedTag: "unused"
        ) == .init(value: "stored", deletesAfterProbe: false))
        #expect(ServerEditLogic.connectionTag(
            existingTag: nil,
            generatedTag: "generated"
        ) == .init(value: "generated", deletesAfterProbe: true))

        let production = ServerEditLogic.connectionTag(existingTag: nil)
        #expect(UUID(uuidString: production.value) != nil)
        #expect(production.deletesAfterProbe)
    }

    private func makeServer() -> OPDSServer {
        OPDSServer(
            name: "Library",
            baseURL: URL(string: "http://books.example/opds")!,
            username: "reader",
            allowInsecureHTTP: true
        )
    }
}
