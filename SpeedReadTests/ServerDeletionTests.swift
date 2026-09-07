import Foundation
import SwiftData
import Testing
@testable import SpeedRead

@Suite("Server deletion effects")
@MainActor
struct ServerDeletionTests {
    @Test func deletesEverySelectedPasswordAndModelButPreservesTheSurvivor() throws {
        // Mutations: drop KeychainStore.deletePassword, delete only one selected server,
        // use offsets against a changing array, or delete the unselected server's credential.
        let container = try ModelContainer(
            for: OPDSServer.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        context.autosaveEnabled = false
        let servers = (0..<3).map {
            OPDSServer(name: "Server \($0)", baseURL: URL(string: "https://example.test")!, username: "")
        }
        defer { for server in servers { try? KeychainStore.deletePassword(for: server.keychainTag) } }
        for server in servers {
            context.insert(server)
            try KeychainStore.setPassword("synthetic-test-password", for: server.keychainTag)
            #expect(KeychainStore.password(for: server.keychainTag) == "synthetic-test-password")
        }
        try context.save()
        ServerListLogic.deleteServers(at: IndexSet([0, 2]), from: servers, modelContext: context)

        #expect(KeychainStore.password(for: servers[0].keychainTag) == nil)
        #expect(KeychainStore.password(for: servers[2].keychainTag) == nil)
        #expect(KeychainStore.password(for: servers[1].keychainTag) == "synthetic-test-password")
        let stored = try ModelContext(container).fetch(FetchDescriptor<OPDSServer>())
        #expect(stored.map(\.id) == [servers[1].id])
        #expect(!context.hasChanges)
    }

    @Test func missingPasswordDoesNotPreventModelDeletion() throws {
        // Mutation: require an existing credential before deleting the model.
        let container = try ModelContainer(
            for: OPDSServer.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let server = OPDSServer(name: "No password", baseURL: URL(string: "https://example.test")!, username: "")
        container.mainContext.insert(server)
        try container.mainContext.save()
        #expect(KeychainStore.password(for: server.keychainTag) == nil)
        ServerListLogic.deleteServers(at: IndexSet(integer: 0), from: [server], modelContext: container.mainContext)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<OPDSServer>()) == 0)
    }
}
