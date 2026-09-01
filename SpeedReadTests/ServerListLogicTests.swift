import Foundation
import Testing
@testable import SpeedRead

@Suite("Server list logic")
struct ServerListLogicTests {
    @Test func deletionOffsetsSelectExactlyTheDisplayedServers() throws {
        let first = makeServer(name: "First", username: "")
        let second = makeServer(name: "Second", username: "reader")
        let third = makeServer(name: "Third", username: "admin")

        let selected = ServerListLogic.serversToDelete(
            at: IndexSet([0, 2]),
            from: [first, second, third]
        )

        #expect(selected.map(\.id) == [first.id, third.id])
        #expect(selected.contains { $0.id == second.id } == false)
    }

    @Test func accountDetailDistinguishesAnonymousAndAuthenticatedServers() {
        #expect(ServerListLogic.accountDetail(username: "") == "anonymous")
        #expect(ServerListLogic.accountDetail(username: "reader") == "user: reader")
    }

    private func makeServer(name: String, username: String) -> OPDSServer {
        OPDSServer(
            name: name,
            baseURL: URL(string: "https://books.example/\(name)")!,
            username: username
        )
    }
}
