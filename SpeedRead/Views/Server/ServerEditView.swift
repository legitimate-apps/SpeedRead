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

    @State private var testState: TestState = .idle
    @State private var validationError: String?

    enum TestState: Equatable {
        case idle
        case running
        case success
        case failure(String)
    }

    private var isEdit: Bool { server != nil }
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
                .disabled(testState == .running || urlString.trimmingCharacters(in: .whitespaces).isEmpty)
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
        .navigationTitle(isEdit ? server?.name ?? "Server" : "New Server")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!canSave)
            }
            if isEdit {
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
        guard let server else { return }
        name = server.name
        urlString = server.baseURLString
        username = server.username
        password = KeychainStore.password(for: server.keychainTag) ?? ""
        allowInsecureHTTP = server.allowInsecureHTTP
    }

    private func save() {
        let url: URL
        switch OPDSServerFormLogic.validateURL(
            urlString,
            allowInsecureHTTP: allowInsecureHTTP
        ) {
        case .valid(let validatedURL):
            url = validatedURL
        case .invalid:
            validationError = "Please enter a valid URL beginning with http:// or https://."
            return
        case .insecureHTTP:
            validationError = "This URL uses http://. Enable “Allow plain HTTP” or switch to https://."
            return
        }
        validationError = nil
        let identity = OPDSServerFormLogic.normalizedIdentity(
            name: name,
            username: username,
            password: password
        )

        if let server {
            server.name = identity.name
            server.baseURLString = url.absoluteString
            server.username = identity.username
            server.allowInsecureHTTP = allowInsecureHTTP
            persistPassword(identity.password, for: server.keychainTag)
        } else {
            let s = OPDSServer(
                name: identity.name,
                baseURL: url,
                username: identity.username,
                allowInsecureHTTP: allowInsecureHTTP,
                sortIndex: Int(Date().timeIntervalSince1970)
            )
            modelContext.insert(s)
            persistPassword(identity.password, for: s.keychainTag)
        }
        try? modelContext.save()
        dismiss()
    }

    private func persistPassword(_ password: String, for tag: String) {
        if password.isEmpty {
            try? KeychainStore.deletePassword(for: tag)
        } else {
            try? KeychainStore.setPassword(password, for: tag)
        }
    }

    private func testConnection() async {
        let url: URL
        switch OPDSServerFormLogic.validateURL(
            urlString,
            allowInsecureHTTP: allowInsecureHTTP
        ) {
        case .valid(let validatedURL):
            url = validatedURL
        case .invalid:
            testState = .failure("Invalid URL")
            return
        case .insecureHTTP:
            testState = .failure("Plain HTTP is disabled for this server")
            return
        }
        testState = .running
        let tag = server?.keychainTag ?? "test-\(UUID().uuidString)"
        if !password.isEmpty {
            try? KeychainStore.setPassword(password, for: tag)
        }
        defer {
            if server == nil { try? KeychainStore.deletePassword(for: tag) }
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
        probeServer.keychainTag = tag

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
