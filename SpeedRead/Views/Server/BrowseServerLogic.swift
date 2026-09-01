//  BrowseServerLogic.swift
//  Pure decisions behind BrowseServerView.swift. In its OWN file deliberately, not by style preference.
//
//  Attributable coverage is measured per FILE. A tested type sharing a file with SwiftUI
//  body markup pulls every one of those untested lines into the denominator, so the
//  metric reports worse the more logic you extract -- which is exactly backwards.
//  MEASURED 2026-09-01 with this type inline: BrowseServerView.swift read 46/798 (5.76%), contributing
//  798 lines to 'attributable'. The two logic types that already lived in their own
//  files read 97.50% and 100.00%. Same tests, same code, different file boundary.
import Foundation
import SwiftData

struct BrowseServerLogic {
    struct ServerSnapshot: Equatable {
        let id: UUID
        let name: String
        let baseURL: URL?

        init(server: OPDSServer) {
            id = server.id
            name = server.name
            baseURL = server.baseURL
        }
    }

    struct FeedDestination: Equatable {
        let serverID: UUID
        let url: URL
        let title: String
    }

    enum Route: Equatable {
        case empty
        case picker
        case feed(FeedDestination)
        case invalidURL(serverName: String)
    }

    enum FeedPresentation: Equatable {
        case loading
        case failure(String)
        case content
    }

    enum PaginationPresentation: Equatable {
        case hidden
        case loading
        case loadMore
    }

    enum ToastPresentation: Equatable {
        case none
        case added(String)
        case failure(String)
    }

    static func route(
        servers: [ServerSnapshot],
        selectedServerID: UUID?
    ) -> Route {
        guard !servers.isEmpty else { return .empty }

        let selected: ServerSnapshot?
        if servers.count == 1 {
            selected = servers[0]
        } else if let selectedServerID {
            selected = servers.first { $0.id == selectedServerID }
        } else {
            selected = nil
        }
        guard let selected else { return .picker }
        guard let url = selected.baseURL,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            return .invalidURL(serverName: selected.name)
        }
        return .feed(.init(
            serverID: selected.id,
            url: url,
            title: selected.name
        ))
    }

    static func feedPresentation(
        loading: Bool,
        hasFeed: Bool,
        error: String?
    ) -> FeedPresentation {
        if loading && !hasFeed { return .loading }
        if let error { return .failure(error) }
        return .content
    }

    static func paginationPresentation(
        nextPageURL: URL?,
        searchText: String,
        loadingMore: Bool
    ) -> PaginationPresentation {
        guard nextPageURL != nil, searchText.isEmpty else { return .hidden }
        return loadingMore ? .loading : .loadMore
    }

    static func toastPresentation(
        completedTitle: String?,
        error: String?
    ) -> ToastPresentation {
        if let completedTitle { return .added(completedTitle) }
        if let error { return .failure(error) }
        return .none
    }
}
