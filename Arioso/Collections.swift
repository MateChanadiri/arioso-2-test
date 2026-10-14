                }
                Menu {
                    ForEach(SourceKind.allCases) { kind in
                        Button { adding = kind } label: { Label(kind.title, systemImage: kind.symbol) }
                    }
                } label: { Label("Add Server", systemImage: "plus.circle.fill") }
                if sources.hasSources {
                    Button { Task { await sources.syncAll() } } label: { Label("Sync All Now", systemImage: "arrow.triangle.2.circlepath") }
                        .disabled(!sources.syncing.isEmpty)
                }
            } header: { Text("Sources") } footer: {
                Text("Songs from your server join your library next to local files — one library, one app. Subsonic works with Navidrome, Gonic, Airsonic, Ampache, Nextcloud Music and other compatible servers.")
            }

            ModulesSection(adding: $addingModule)

            if sources.hasSources || !ModuleStore.shared.modules.isEmpty {
                Section("Streaming") {
                    Picker("Wi-Fi Quality", selection: $sources.streamBitrate) { qualityOptions }
                    Picker("Cellular Quality", selection: $sources.cellularBitrate) { qualityOptions }
                    Picker("Download Quality", selection: $sources.downloadBitrate) { qualityOptions }
                    Toggle("Sync on Launch", isOn: $sources.autoSync)
                    Toggle("Skip Songs I Have Locally", isOn: $sources.skipLocalDuplicates)
                }
                Section {
                    Toggle(isOn: $settings.offlineMode) { Label("Offline Mode", systemImage: "icloud.slash") }
                    Picker("Stream Cache", selection: $cacheMB) {
                        Text("256 MB").tag(256); Text("512 MB").tag(512); Text("1 GB").tag(1024); Text("2 GB").tag(2048); Text("5 GB").tag(5120)
                    }
                    LabeledContent("Cache in Use", value: ByteCountFormatter.string(fromByteCount: cacheSize, countStyle: .file))
                    Button("Clear Stream Cache", role: .destructive) { StreamCache.clear(); cacheSize = 0 }
                    if !sources.pending.isEmpty {
                        LabeledContent("Waiting to Sync", value: "\(sources.pending.count) changes")
                    }
                } header: { Text("Offline") } footer: {
                    Text("Offline Mode only plays music on this iPhone. Favorites and plays made offline are sent to your server when you're back online.")
                }
            }
        }
        .navigationTitle("Sources")
        .navigationBarTitleDisplayMode(.inline)
        .task { cacheSize = await Task.detached { StreamCache.size }.value }
        .sheet(item: $adding) { ServerLoginView(kind: $0) }
        .sheet(isPresented: $addingModule) { AddModuleSheet() }
    }

    @ViewBuilder private var qualityOptions: some View {
        Text("Original").tag(0)
        Text("320 kbps").tag(320)
        Text("256 kbps").tag(256)
        Text("192 kbps").tag(192)
        Text("128 kbps").tag(128)
    }
}

struct ServerLoginView: View {
    let kind: SourceKind
    var embedded = false
    @Environment(SourceManager.self) private var sources
    @Environment(\.dismiss) private var dismiss
    @State private var server = ""
    @State private var user = ""
    @State private var password = ""
    @State private var working = false
    @State private var error: String?

    var body: some View {
        if embedded { form } else { NavigationStack { form } }
    }

    private var form: some View {
        Form {
            Section {
                TextField("Server Address", text: $server, prompt: Text(kind == .jellyfin ? "jellyfin.local:8096" : "navidrome.local:4533"))
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .textContentType(.URL)
                TextField("User Name", text: $user).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .textContentType(.username)
                SecureField("Password", text: $password).textContentType(.password)
            } footer: {
                Text(kind == .jellyfin
                     ? "Your password is only used to sign in; Music keeps the access token in the Keychain."
                     : "Subsonic servers check the password on every request, so Music keeps it in the Keychain and sends a salted hash where the server supports it.")
            }
            if let error { Section { Text(error).foregroundStyle(.red) } }
        }
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .disabled(working)
        .toolbar {
            if !embedded { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            ToolbarItem(placement: .confirmationAction) {
                if working { ProgressView() } else {
                    Button("Sign In") {
                        working = true
                        error = nil
                        Task {
                            do {
                                switch kind {
                                case .jellyfin: try await sources.addJellyfin(server: server, user: user, password: password)
                                case .subsonic: try await sources.addSubsonic(server: server, user: user, password: password)
                                }
                                dismiss()
                            } catch let e {
                                error = e.localizedDescription
                            }
                            working = false
                        }
                    }
                    .disabled(server.isEmpty || user.isEmpty)
                }
            }
        }
    }
}
