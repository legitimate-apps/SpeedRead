//  ServerEditView.swift
import SwiftUI
import SwiftData

struct ServerEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager

    let server: OPDSServer?

    @State private var name: String = ""
    @State private var urlString: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var allowInsecureHTTP: Bool = false

    @State private var testState: ServerEditLogic.ConnectionState = .idle
    @State private var validationError: String?

    private var presentation: ServerEditLogic.Presentation {
        ServerEditLogic.presentation(server: server)
    }

    private var pendingHTTP: Bool {
        OPDSServerFormLogic.isPendingPlainHTTP(urlString)
    }

    var body: some View {
        Form {
            Section("Server") {
                TextField("Friendly name", text: $name)
                    .autocorrectionDisabled()
                TextField("https://books.example.com/opds", text: $urlString)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section {
                TextField("Username (leave empty for anonymous)", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Authentication")
            } footer: {
                Text("Credentials are stored in the iOS Keychain on this device only.")
            }

            Section {
                Toggle(isOn: $allowInsecureHTTP) {
                    Label("Allow plain HTTP", systemImage: pendingHTTP && !allowInsecureHTTP ? "exclamationmark.shield" : "lock.shield")
                }
            } header: {
                Text("Security")
            } footer: {
                if pendingHTTP && !allowInsecureHTTP {
                    Text("This server uses http://. Enable plain HTTP or change the URL to https://.")
                        .foregroundStyle(Color.crimsonSoft)
                } else {
                    Text("Only enable plain HTTP for trusted local-network servers. HTTPS is recommended.")
                }
            }

            Section {
                Button {
                    Task { await testConnection() }
                } label: {
                    HStack {
                        switch testState {
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
                    state: testState,
                    urlString: urlString
                ))
            }

            if let validationError {
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
                Button("Save") { save() }
                    .disabled(!canSave)
            }
            if presentation.showsCancel {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear(perform: loadExisting)
    }

    private var canSave: Bool {
        OPDSServerFormLogic.canSave(name: name, urlString: urlString)
    }

    private func loadExisting() {
        let values = ServerEditLogic.initialValues(server: server)
        name = values.name
        urlString = values.urlString
        username = values.username
        password = values.password
        allowInsecureHTTP = values.allowInsecureHTTP
    }

    private func save() {
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
            return
        case .valid(let value):
            validated = value
        }
        validationError = nil

        if let server {
            server.name = validated.name
            server.baseURLString = validated.url.absoluteString
            server.username = validated.username
            server.allowInsecureHTTP = validated.allowInsecureHTTP
            persistPassword(validated.password, for: server.keychainTag)
        } else {
            let s = OPDSServer(
                name: validated.name,
                baseURL: validated.url,
                username: validated.username,
                allowInsecureHTTP: validated.allowInsecureHTTP,
                sortIndex: ServerEditLogic.sortIndex()
            )
            modelContext.insert(s)
            persistPassword(validated.password, for: s.keychainTag)
        }
        try? modelContext.save()
        dismiss()
    }

    private func persistPassword(_ password: String, for tag: String) {
        switch ServerEditLogic.passwordAction(password: password) {
        case .delete:
            try? KeychainStore.deletePassword(for: tag)
        case .set(let value):
            try? KeychainStore.setPassword(value, for: tag)
        }
    }

    private func testConnection() async {
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

        let client = OPDSClient()
        do {
            _ = try await client.testConnection(probeServer)
            testState = .success
        } catch let opdsError as OPDSError {
            testState = .failure(opdsError.errorDescription ?? "Unknown error")
        } catch {
            testState = .failure(error.localizedDescription)
        }
    }
}
