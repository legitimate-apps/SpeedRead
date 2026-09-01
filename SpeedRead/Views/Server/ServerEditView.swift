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

struct ServerEditLogic {
    struct FormValues: Equatable {
        let name: String
        let urlString: String
        let username: String
        let password: String
        let allowInsecureHTTP: Bool

        static let empty = FormValues(
            name: "",
            urlString: "",
            username: "",
            password: "",
            allowInsecureHTTP: false
        )
    }

    struct Presentation: Equatable {
        let navigationTitle: String
        let showsCancel: Bool
    }

    enum ConnectionState: Equatable {
        case idle
        case running
        case success
        case failure(String)
    }

    struct ValidatedServer: Equatable {
        let url: URL
        let name: String
        let username: String
        let password: String
        let allowInsecureHTTP: Bool
    }

    enum SaveDecision: Equatable {
        case valid(ValidatedServer)
        case failure(String)
    }

    enum ConnectionDecision: Equatable {
        case probe(URL)
        case failure(String)
    }

    enum PasswordAction: Equatable {
        case delete
        case set(String)
    }

    struct ConnectionTag: Equatable {
        let value: String
        let deletesAfterProbe: Bool
    }

    static func initialValues(
        server: OPDSServer?,
        passwordForTag: (String) -> String? = KeychainStore.password(for:)
    ) -> FormValues {
        guard let server else { return .empty }
        return FormValues(
            name: server.name,
            urlString: server.baseURLString,
            username: server.username,
            password: passwordForTag(server.keychainTag) ?? "",
            allowInsecureHTTP: server.allowInsecureHTTP
        )
    }

    static func presentation(server: OPDSServer?) -> Presentation {
        guard let server else {
            return Presentation(navigationTitle: "New Server", showsCancel: false)
        }
        return Presentation(navigationTitle: server.name, showsCancel: true)
    }

    static func canTestConnection(
        state: ConnectionState,
        urlString: String
    ) -> Bool {
        state != .running
            && !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func saveDecision(
        name: String,
        urlString: String,
        username: String,
        password: String,
        allowInsecureHTTP: Bool
    ) -> SaveDecision {
        let url: URL
        switch OPDSServerFormLogic.validateURL(
            urlString,
            allowInsecureHTTP: allowInsecureHTTP
        ) {
        case .valid(let validatedURL):
            url = validatedURL
        case .invalid:
            return .failure("Please enter a valid URL beginning with http:// or https://.")
        case .insecureHTTP:
            return .failure("This URL uses http://. Enable “Allow plain HTTP” or switch to https://.")
        }
        let identity = OPDSServerFormLogic.normalizedIdentity(
            name: name,
            username: username,
            password: password
        )
        return .valid(.init(
            url: url,
            name: identity.name,
            username: identity.username,
            password: identity.password,
            allowInsecureHTTP: allowInsecureHTTP
        ))
    }

    static func connectionDecision(
        urlString: String,
        allowInsecureHTTP: Bool
    ) -> ConnectionDecision {
        switch OPDSServerFormLogic.validateURL(
            urlString,
            allowInsecureHTTP: allowInsecureHTTP
        ) {
        case .valid(let url):
            return .probe(url)
        case .invalid:
            return .failure("Invalid URL")
        case .insecureHTTP:
            return .failure("Plain HTTP is disabled for this server")
        }
    }

    static func passwordAction(password: String) -> PasswordAction {
        password.isEmpty ? .delete : .set(password)
    }

    static func sortIndex(now: Date = Date()) -> Int {
        Int(now.timeIntervalSince1970)
    }

    static func connectionTag(
        existingTag: String?,
        generatedTag: String = UUID().uuidString
    ) -> ConnectionTag {
        if let existingTag {
            return ConnectionTag(value: existingTag, deletesAfterProbe: false)
        }
        return ConnectionTag(value: generatedTag, deletesAfterProbe: true)
    }
}
