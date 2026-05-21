//  SettingsView.swift
import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.currentTheme.backgroundColor.ignoresSafeArea()
                Form {
                    Section {
                        NavigationLink {
                            ServerListView()
                        } label: {
                            Label("Library Servers", systemImage: "icloud")
                                .foregroundStyle(Color.crimsonSoft)
                        }
                    } header: {
                        Text("Remote Libraries")
                    } footer: {
                        Text("Connect to Calibre, Calibre-Web, Calibre-Web-NextGen, or any other catalog that speaks OPDS.")
                    }

                    Section("About") {
                        LabeledContent("Version") {
                            Text(versionString)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.crimsonSoft)
                }
            }
        }
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}
