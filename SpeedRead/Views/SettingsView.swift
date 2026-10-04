//  SettingsView.swift
import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appSurface.ignoresSafeArea()
                Form {
                    Section {
                        NavigationLink {
                            ServerListView()
                        } label: {
                            Label {
                                Text("Library Servers")
                                    .foregroundStyle(Color.appInk)
                            } icon: {
                                Image(systemName: "icloud")
                                    .foregroundStyle(Color.appAccent)
                            }
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
                .listRowBackground(Color.appSurfaceRaised)
                .tint(Color.appAccent)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appSurface, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.appAccent)
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
