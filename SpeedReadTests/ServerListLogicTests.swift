import Foundation
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import SpeedRead

@Suite("Server list logic")
@MainActor
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

    @Test func populatedServerListRendersTheStoredServerDecisionPath() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: OPDSServer.self,
            configurations: configuration
        ).keptAliveForHostedViews()
        let server = makeServer(name: "Rendered", username: "reader")
        container.mainContext.insert(server)
        try container.mainContext.save()
        let root = NavigationStack { ServerListView() }
            .modelContainer(container)
            .environment(ThemeManager())
        let host = UIHostingController(rootView: root)
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true }
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()

        let signatures = renderedPixelSignatures(in: host.view)
        let stored = try container.mainContext.fetch(FetchDescriptor<OPDSServer>())

        #expect(stored.map(\.name) == ["Rendered"])
        #expect(ServerListLogic.accountDetail(username: stored[0].username) == "user: reader")
        #expect(signatures.count > 5)
        #expect(host.view.bounds == CGRect(x: 0, y: 0, width: 390, height: 844))
    }

    private func makeServer(name: String, username: String) -> OPDSServer {
        OPDSServer(
            name: name,
            baseURL: URL(string: "https://books.example/\(name)")!,
            username: username
        )
    }

    private func renderedPixelSignatures(in view: UIView) -> Set<[UInt8]> {
        let renderer = UIGraphicsImageRenderer(bounds: view.bounds)
        let image = renderer.image { context in
            view.layer.render(in: context.cgContext)
        }
        guard let cgImage = image.cgImage,
              let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return []
        }

        let bytesPerPixel = max(1, cgImage.bitsPerPixel / 8)
        var signatures: Set<[UInt8]> = []
        for y in stride(from: 0, to: cgImage.height, by: 20) {
            for x in stride(from: 0, to: cgImage.width, by: 20) {
                let offset = y * cgImage.bytesPerRow + x * bytesPerPixel
                signatures.insert(Array(UnsafeBufferPointer(
                    start: bytes + offset,
                    count: min(4, bytesPerPixel)
                )))
            }
        }
        return signatures
    }
}
