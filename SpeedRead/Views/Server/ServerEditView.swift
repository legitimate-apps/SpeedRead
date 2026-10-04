//  ServerEditView.swift
import SwiftUI
import SwiftData

struct ServerEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.opdsClientFactory) private var makeClient
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager

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
                TextField("https://books.example.com/opds", text: $session.urlString)
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
                        .foregroundStyle(Color.crimsonSoft)
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
                Text("For books downloaded from this server: your place, highlights, notes and bookmarks are saved to it, and you get the ones you made in other readers that sync with it. Only servers that support text-anchored sync are used.")
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
                                .foregroundStyle(.green)
                        case .failure(let msg):
                            Label(msg, systemImage: "xmark.octagon")
                                .foregroundStyle(Color.crimsonSoft)
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
                        .foregroundStyle(Color.crimsonSoft)
                        .font(.footnote)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(themeManager.currentTheme.backgroundColor)
        .navigationTitle(presentation.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
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
