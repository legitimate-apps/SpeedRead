# SpeedRead — OPDS Client Integration

**Status:** Draft for review
**Date:** 2026-05-21
**Author:** Legitimate LLC + Claude
**Scope:** Add OPDS catalog browsing, search, and download to SpeedRead. Multi-server, HTTP-or-HTTPS, no changes to any server.

## Why

SpeedRead today is a strictly-local e-reader: books arrive via the file picker or
the bundled sample loader, and there is no concept of a remote source. Many
users (including the project owner) self-host an OPDS-capable library server —
Calibre-Web-NextGen is the primary target, but the same code works against
stock Calibre's content server, Calibre-Web, Calibre-Web-Automated, Standard
Ebooks, Project Gutenberg, and any other OPDS 1.x catalog.

Building SpeedRead as a standards-compliant OPDS client (rather than a
CWNG-specific client) means:

- Zero server-side work — CWNG already implements OPDS 1.x richly
- One implementation works against every OPDS catalog the user might add later
- No fork-coupling: SpeedRead does not depend on any CWNG-specific endpoint,
  schema, or auth flow
- Mirrors how every other major e-reader integrates with library servers
  (Aldiko, Moon+ Reader, KyBook, Marvin, Calibre Companion, KOReader, etc.)

## Non-goals (v1)

- **No reading-position sync to the server.** Progress, bookmarks, and
  highlights stay local-only. Sync (via KOReader kosync, Kobo sync, or
  anything else) is a separate future feature with its own design.
- **No annotation upload.** SpeedRead's `Bookmark` / `Highlight` models are
  not pushed anywhere remote.
- **No upload/write to the server.** SpeedRead never adds, edits, or deletes
  books on the OPDS source — even when OPDS extensions permit it.
- **No streaming reads.** Books are downloaded fully to local storage; the
  existing `Data → extractor → Book.extractedText` pipeline is preserved
  unchanged. (Streaming would break the Watch sync model, which currently
  assumes full text on the phone.)
- **No OPDS 2.0 (JSON) support yet.** OPDS 1.x (Atom) covers all current
  targets; OPDS 2.0 can be added later as a parser-level alternative without
  touching the rest of the stack.
- **No replacement of the file-picker import path.** Local import keeps
  working exactly as today.

## Test target

Primary integration target is the live CWNG instance on my server.
Fallback: a local `docker compose` spin-up of `crocodilestick/calibre-web-automated`
or a CWNG instance (which is what the live target runs anyway). Both
paths are exercised during development.

CI does not need a live server — XML parsing and client logic are tested with
fixture Atom feeds captured from the live CWNG; networking is mocked at the
`URLProtocol` layer.

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│  SwiftUI Views                                            │
│  ┌───────────────┐  ┌────────────────┐  ┌──────────────┐ │
│  │ LibraryView   │  │ BrowseServer   │  │ ServerEdit / │ │
│  │ (cloud toolbar│→│ View (sheet)   │←│ ServerList   │ │
│  │  button)      │  │                 │  │ (Settings)   │ │
│  └───────────────┘  └────────┬────────┘  └──────┬───────┘ │
│                              │                   │         │
└──────────────────────────────┼───────────────────┼─────────┘
                               │                   │
                ┌──────────────▼───────────────────▼─────┐
                │  OPDSClient (actor)                     │
                │  - fetchFeed(url:) → OPDSFeed           │
                │  - download(url:) → Data                │
                │  - testConnection(server:) → Bool       │
                │  - URLSession + Basic Auth headers      │
                │  - Honors per-server allowInsecure flag │
                └──────┬──────────────────────┬───────────┘
                       │                       │
        ┌──────────────▼────────┐    ┌─────────▼───────────┐
        │ OPDSAtomParser        │    │ KeychainStore       │
        │ (XMLParserDelegate)   │    │ (Security framework)│
        │ → OPDSFeed/OPDSEntry  │    │ store/load/delete   │
        └───────────────────────┘    └─────────────────────┘

        ┌─────────────────────────────────────┐
        │ DocumentImporter (existing, extended)│
        │ + importData(_:filename:context:)    │  ← new entry, no security-scoping
        │   importFile(at:) (existing path)    │
        └──────────────┬──────────────────────┘
                       │
                       ▼
                  SwiftData: Book
                       │
                       ▼
               WatchSyncService.sendBook  (unchanged)
```

## Components

### `Models/OPDSServer.swift` (new)

SwiftData `@Model`:

```swift
@Model final class OPDSServer {
    @Attribute(.unique) var id: UUID
    var name: String                 // user-provided friendly name
    var baseURL: URL                 // root OPDS URL (e.g. https://calibre.example.com/opds)
    var username: String             // empty string = anonymous
    var keychainTag: String          // UUID-string; key under which password lives in Keychain
    var allowInsecureHTTP: Bool      // per-server; default false
    var lastUsedAt: Date?
    var sortIndex: Int               // display order in server list

    init(name: String, baseURL: URL, username: String, allowInsecureHTTP: Bool)
}
```

Password is never stored on the `@Model`. The `keychainTag` is a stable
identifier used as the Keychain account key. Deleting an `OPDSServer` cascades
into a Keychain delete.

### `Services/KeychainStore.swift` (new)

Minimal wrapper around `SecItemAdd` / `SecItemCopyMatching` / `SecItemDelete`
using kSecClassGenericPassword. Service = `com.legitimateapps.SpeedRead.opds`,
Account = `keychainTag`. No third-party dep.

```swift
enum KeychainStore {
    static func setPassword(_ password: String, for tag: String) throws
    static func password(for tag: String) -> String?
    static func deletePassword(for tag: String) throws
}
```

### `Services/OPDSClient.swift` (new)

`actor` wrapping a `URLSession`. The session uses an ephemeral configuration
plus a per-server URLSessionDelegate that injects `Authorization: Basic ...`
when username is non-empty.

```swift
actor OPDSClient {
    func fetchFeed(url: URL, on server: OPDSServer) async throws -> OPDSFeed
    func download(from url: URL, on server: OPDSServer) async throws -> (Data, String)  // data + filename
    func testConnection(_ server: OPDSServer) async throws -> Bool
}
```

`testConnection` fetches the root feed and verifies it parses to at least one
`<entry>` or `<link rel="...">`.

**HTTP policy:** if `server.allowInsecureHTTP` is `true` and the URL scheme is
`http`, the request is allowed through; otherwise non-HTTPS schemes throw
`OPDSError.insecureSchemeBlocked`. ATS is configured globally to allow
arbitrary loads (see Info.plist below) so the runtime gate becomes the only
enforcement point, surfaced clearly in Server Edit.

### `Services/OPDSAtomParser.swift` (new)

`XMLParserDelegate` implementation that produces:

```swift
struct OPDSFeed {
    let title: String
    let entries: [OPDSEntry]
    let navigationLinks: [OPDSLink]   // rel=subsection / start / up / search / next / prev
    let searchDescriptionURL: URL?    // from rel="search" type="application/opensearchdescription+xml"
    let nextPageURL: URL?
}

struct OPDSEntry {
    let id: String
    let title: String
    let authors: [String]
    let summary: String?
    let updated: Date?
    let coverURL: URL?                // OPDS thumbnail rel="http://opds-spec.org/image/thumbnail"
    let fullCoverURL: URL?            // rel="http://opds-spec.org/image"
    let acquisitionLinks: [OPDSAcquisition]   // rel="http://opds-spec.org/acquisition"
}

struct OPDSAcquisition {
    let url: URL
    let mimeType: String              // application/epub+zip, application/pdf, application/x-mobipocket-ebook, ...
}

struct OPDSLink {
    let rel: String
    let url: URL
    let title: String?
    let type: String?
}
```

Resolves all relative URLs against the feed's `<id>` or the request URL.

OPDS namespaces handled: Atom (`http://www.w3.org/2005/Atom`), Dublin Core
(`http://purl.org/dc/terms/`), OPDS (`http://opds-spec.org/2010/catalog`).
Element coalescing is whitespace-trimmed.

### `Services/DocumentImporter.swift` (extended, not replaced)

Add a sibling entry:

```swift
extension DocumentImporter {
    static func importData(
        _ data: Data,
        filename: String,
        modelContext: ModelContext
    ) throws -> Book
}
```

Routes by extension just like `importFile(at:)`. The existing
`importFile(at:)` keeps working for the file picker. No behavior change to
local imports.

### Views (new)

- **`Views/Server/ServerListView.swift`** — settings entry, lists saved
  servers, add/edit/delete, reorder via drag handle. Empty state explains
  what OPDS is in one sentence.
- **`Views/Server/ServerEditView.swift`** — form: friendly name, base URL,
  username (optional), password (secure field, stored to Keychain on save),
  toggle "Allow plain HTTP for this server" with a warning subtitle, and a
  "Test Connection" button that invokes `OPDSClient.testConnection`.
- **`Views/Server/BrowseServerView.swift`** — entry sheet for the cloud
  toolbar button. If exactly one server is saved, jumps directly to its
  root feed; if multiple, shows the server picker first. Renders the
  current `OPDSFeed`: navigation links as a list (drill-down via
  `NavigationStack`), entries as a book-card list with cover thumbnails,
  pull-to-refresh, infinite scroll via `nextPageURL`. Search bar uses the
  `searchDescriptionURL` OpenSearch template.
- **`Views/Server/RemoteBookDetailView.swift`** — full metadata, large
  cover, format picker (if multiple acquisition links), "Download &
  Add to Library" button that calls `OPDSClient.download` and
  `DocumentImporter.importData`. Progress reported via a `Task` + a
  determinate progress view backed by `URLSession`'s
  `bytesReceived`/`totalBytesExpected`.

### `Views/LibraryView.swift` (modified)

Add a toolbar item next to the existing file-picker plus button:

- **Cloud icon (`icloud.and.arrow.down`)**: opens `BrowseServerView` as a sheet.
- Disabled with onboarding hint if no servers are configured (taps go to
  Settings → Servers).

A new `Settings` button (gear icon) in the toolbar links to a `SettingsView`
(also new — the project has none today), which contains:
- **Servers** section → `ServerListView`
- Hooks for future settings (existing AppStorage flags are not migrated in
  v1; they keep living on the views that use them, since this spec is
  focused on remote-library only)

## Data flow: download path

1. User taps "Download & Add" on `RemoteBookDetailView`.
2. `OPDSClient.download(from: acquisitionURL, on: server)` opens a
   `URLSession.bytes(for:)` stream, applying Basic Auth.
3. Bytes accumulate into a `Data` buffer; progress publishes to a UI
   `@Observable` download coordinator.
4. On completion, filename is derived from `Content-Disposition` header (with
   fallback to the URL last path component or to `<book.title>.<ext>`).
5. `DocumentImporter.importData(_, filename:, modelContext:)` routes to the
   right extractor and constructs a `Book`.
6. SwiftData saves; library view's `@Query` picks up the new row.
7. The book is locally identical to any file-picker import — Watch sync,
   RSVP, reader, bookmarks, highlights all work without further changes.

## Error handling

Surfaced via a `OPDSError` enum:

- `.networkError(Error)` — URLSession failure
- `.httpError(status: Int, body: String?)` — non-2xx response (401, 403,
  404, 5xx); shown to user with status-code context
- `.invalidURL`
- `.parseError(line: Int?)` — XML parser failure
- `.unsupportedFormat(String)` — acquisition mimetype outside SpeedRead's
  extractor set; user gets a clear message instead of a silent failure
- `.insecureSchemeBlocked` — http URL when the server's allowInsecureHTTP is
  off; suggests turning the toggle on or migrating to HTTPS
- `.cancelled` — user cancelled mid-download

Server-edit "Test Connection" surfaces these directly. Browse failures show
inline retry. Download failures show a toast + leave no partial `Book` in
SwiftData (the insert is the last step, after the data is fully in memory).

## Info.plist changes

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

Justification (App Store review note saved alongside the spec): SpeedRead is
a self-host-friendly e-reader; users may run their OPDS server on the local
network or behind reverse proxies that terminate TLS upstream. The per-server
"Allow plain HTTP" toggle is the user-facing enforcement; ATS is opened to
allow that toggle to function. HTTPS remains the default in the Server Edit
form and the toggle is labeled with a security warning.

## Testing

Two layers.

### Unit (Swift Testing, in `SpeedReadTests/`)

- `OPDSAtomParserTests` — fixture-driven. Capture real Atom XML from live
  CWNG (sanitized of any private library metadata before committing) for:
  root feed, search feed, by-author drill-down, paginated feed (multi-page),
  entry with multiple acquisition links, entry with no cover, malformed
  feed (parser recovers). One fixture per case in
  `SpeedReadTests/Fixtures/OPDS/`.
- `OPDSClientTests` — uses a custom `URLProtocol` to intercept requests,
  inject canned responses (200 + fixture, 401, 5xx, redirect chain).
  Verifies Basic Auth header is exactly what the server expects, HTTP
  scheme is gated by `allowInsecureHTTP`, basic-auth realm-aware redirect
  follows, large-body streaming completes.
- `KeychainStoreTests` — round-trip set/get/delete; verifies wipe on
  `OPDSServer` deletion.
- `DocumentImporterTests` — `importData(_:filename:context:)` happy path
  for each extractor; reject unsupported mimetypes; verify resulting
  `Book.wordCount` matches `tokenize(_:).count`.

### Integration (manual + scripted, against live CWNG on my server)

Documented as a checklist in `docs/plans/<date>-opds-client-rollout.md`
(separate plan doc, not part of the spec):

- Configure SpeedRead with my server's CWNG URL and a read-only test
  user account on that server.
- Browse root → Recently Added → drill into a book → download EPUB → open
  in reader → tap a word → RSVP starts → close → red-highlight at last-read
  position appears. (End-to-end happy path.)
- Repeat with PDF.
- Search for a known title; verify result list and download.
- Toggle the test server to HTTP scheme (point at my server over LAN) +
  enable insecure toggle; verify download still works.
- Disable insecure toggle on the HTTP server; verify
  `OPDSError.insecureSchemeBlocked` surfaces in Server Edit and Browse.
- Add a second server (e.g. Standard Ebooks public OPDS, no auth required) —
  verify multi-server picker shows up, anonymous auth works.
- Delete a server — verify Keychain entry is wiped (check via
  `security find-generic-password`).
- Watch app smoke test — a server-downloaded book should sync to the watch
  identically to a file-imported book.

### What is not tested in v1

- 401 / 403 user-facing flows beyond the message string (no auto-retry
  prompt for new credentials; user goes back to Server Edit manually).
- OPDS 2.0 / JSON feeds.
- OpenSearch suggestions endpoint (only the description doc + query
  template).

## File-level deliverables

New files:
- `SpeedRead/Models/OPDSServer.swift`
- `SpeedRead/Services/KeychainStore.swift`
- `SpeedRead/Services/OPDSClient.swift`
- `SpeedRead/Services/OPDSAtomParser.swift`
- `SpeedRead/Services/OPDSDownloadCoordinator.swift` (small `@Observable` for
  progress reporting; could fold into `OPDSClient` but separate keeps it
  testable)
- `SpeedRead/Views/SettingsView.swift`
- `SpeedRead/Views/Server/ServerListView.swift`
- `SpeedRead/Views/Server/ServerEditView.swift`
- `SpeedRead/Views/Server/BrowseServerView.swift`
- `SpeedRead/Views/Server/RemoteBookDetailView.swift`
- `SpeedRead/Views/Server/OPDSEntryRowView.swift` (book card)
- `SpeedReadTests/OPDSAtomParserTests.swift`
- `SpeedReadTests/OPDSClientTests.swift`
- `SpeedReadTests/KeychainStoreTests.swift`
- `SpeedReadTests/DocumentImporterDataTests.swift`
- `SpeedReadTests/Fixtures/OPDS/*.xml`

Modified files:
- `SpeedRead/Services/DocumentImporter.swift` — add `importData(_:filename:context:)`
- `SpeedRead/Views/LibraryView.swift` — add cloud + settings toolbar buttons
- `SpeedRead/SpeedReadApp.swift` — register `OPDSServer` in the SwiftData
  `modelContainer` schema
- `SpeedRead/Info.plist` — `NSAllowsArbitraryLoads = true` (per the
  justification above)

No watch-side changes. Watch sync continues to work as-is — a server-sourced
`Book` is structurally identical to a file-picker `Book`.

## Risks / open questions

- **Basic Auth password lifetime.** Stored in Keychain with default
  accessibility (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`).
  Suitable for non-shared-device personal use; if the user wants
  multi-device propagation later (e.g., via iCloud Keychain) it's a
  one-line attribute change. Documented but not implemented in v1.
- **OPDS feeds with non-standard extensions.** Some servers add custom
  `<calibre:*>` or `<dcterms:*>` metadata. v1 parser ignores unknown
  elements (consistent with OPDS spec) but logs them at `.debug` so we
  can extend later.
- **CWNG's three cover sizes vs. generic OPDS thumbnails.** OPDS spec has
  one thumbnail link and one full image link; CWNG returns whichever size
  the OPDS template chose. We honor the OPDS-declared link and don't
  hardcode CWNG's size variants — keeps generic OPDS servers working.
- **App Store review and ATS.** Some reviewers ask for justification when
  `NSAllowsArbitraryLoads` is set. The "user-configurable self-hosted
  library server" rationale is well-precedented (Aldiko, KyBook,
  KOReader iOS, Marvin all do this); we document the rationale in the
  release notes for review.

## Out of scope (explicit re-statement)

- Reading-position sync, annotation sync, two-way write to server,
  streaming reads, OPDS 2.0 / JSON, KOReader kosync, Kobo sync, Hardcover,
  custom-column-aware metadata, format conversion request flows
  (CWNG converts transparently on download — we don't surface a "request
  conversion" UI in v1), and any UI for managing the server's library.
  Each of these is a candidate for a follow-up spec.
