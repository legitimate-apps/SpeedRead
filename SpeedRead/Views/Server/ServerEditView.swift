//  ServerEditView.swift
import SwiftUI
import SwiftData

struct ServerEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.opdsClientFactory) private var makeClient
    @Environment(\.dismiss) private var dismiss

    let server: OPDSServer?

    @State private var session: ServerEditSession

    init(server: OPDSServer?, session: ServerEditSession? = nil) {
        self.server = server
        _session = State(initialValue: session ?? ServerEditSession())
    }

    private var presentation: ServerEditLogic.Presentation {
        ServerEditLogic.presentation(server: server)
    }

    private var pendingHTTP: Bool {
        OPDSServerFormLogic.isPendingPlainHTTP(session.urlString)
    }

    var body: some View {
        Form {
            Section("Server") {
                TextField("Friendly name", text: $session.name)
                    .autocorrectionDisabled()
                // Verbatim: a localized placeholder parses as Markdown, and its URL draws as a system-blue link.
                TextField("Server address", text: $session.urlString,
                          prompt: Text(verbatim: "https://books.example.com/opds"))
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section {
                TextField("Username (leave empty for anonymous)", text: $session.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $session.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Authentication")
            } footer: {
                Text("Credentials are stored in the iOS Keychain on this device only.")
            }

            Section {
                Toggle(isOn: $session.allowInsecureHTTP) {
                    Label("Allow plain HTTP", systemImage: pendingHTTP && !session.allowInsecureHTTP ? "exclamationmark.shield" : "lock.shield")
                }
            } header: {
                Text("Security")
            } footer: {
                if pendingHTTP && !session.allowInsecureHTTP {
                    Text("This server uses http://. Enable plain HTTP or change the URL to https://.")
                        .foregroundStyle(Color.appError)
                } else {
                    Text("Only enable plain HTTP for trusted local-network servers. HTTPS is recommended.")
                }
            }

            Section {
                Toggle(isOn: $session.syncsReadingPosition) {
                    Label("Sync position and highlights", systemImage: "arrow.triangle.2.circlepath")
                }
                .accessibilityIdentifier("server-sync-position-toggle")
            } header: {
                Text("Reading Sync")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if let server, let problem = ServerPositionSync.shared.problem(for: server.id) {
                        Text(problem.message)
                            .foregroundStyle(Color.appError)
                    }
                    Text("For books downloaded from this server: your place, highlights, notes and bookmarks are saved to it, and you get the ones you made in other readers that sync with it. Only servers that support text-anchored sync are used.")
                }
            }

            Section {
                Button {
                    Task { await session.testConnection(server: server, makeClient: makeClient) }
                } label: {
                    HStack {
                        switch session.testState {
                        case .idle:
                            Label("Test Connection", systemImage: "network")
                        case .running:
                            ProgressView()
                            Text("Testing…")
                        case .success:
                            Label("Connection OK", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Color.appSuccess)
                        case .failure(let msg):
                            Label(msg, systemImage: "xmark.octagon")
                                .foregroundStyle(Color.appError)
                        }
                    }
                }
                .disabled(!ServerEditLogic.canTestConnection(
                    state: session.testState,
                    urlString: session.urlString
                ))
            }

            if let validationError = session.validationError {
                Section {
                    Text(validationError)
                        .foregroundStyle(Color.appError)
                        .font(.footnote)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .listRowBackground(Color.appSurfaceRaised)
        .tint(Color.appAccent)
        .background(Color.appSurface)
        .navigationTitle(presentation.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.appSurface, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    if session.save(server: server, modelContext: modelContext) { dismiss() }
                }
                    .disabled(!session.canSave)
            }
            if presentation.showsCancel {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear { session.loadExisting(server: server) }
    }

}
