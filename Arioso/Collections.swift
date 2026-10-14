import SwiftUI
import Observation

// MARK: - Tabs

nonisolated enum TabKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case home, new, radio, library, search
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .home: "Home"
        case .new: "New"
        case .radio: "Radio"
        case .library: "Library"
        case .search: "Search"
        }
    }
    
    var icon: String {
        switch self {
        case .home: "house.fill"
        case .new: "sparkles"
        case .radio: "dot.radiowaves.left.and.right"
        case .library: "music.note.list"
        case .search: "magnifyingglass"
        }
    }
}

nonisolated struct TabItemConfig: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var kind: TabKind
    var title: String
    var icon: String
    var targetKind: LibraryEntry.Kind?
    var targetKey: String?

    init(kind: TabKind, title: String? = nil, icon: String? = nil, targetKind: LibraryEntry.Kind? = nil, targetKey: String? = nil) {
        self.id = kind.rawValue
        self.kind = kind
        self.title = title ?? kind.title
        self.icon = icon ?? kind.icon
        self.targetKind = targetKind
        self.targetKey = targetKey
    }

    var appTab: AppTab {
        switch kind {
        case .home: .home
        case .library: .library
        default: .custom(id)
        }
    }
}

extension TabItemConfig {
    @ViewBuilder var rootView: some View {
        switch kind {
        case .home: HomeView()
        case .library: LibraryView()
        case .new: NewView().themedBackground()
        case .radio: RadioView().themedBackground()
        case .search: SearchView().themedBackground()
        }
    }
}

// MARK: - Home sections & shortcuts

nonisolated enum HomeSection: String, Codable, CaseIterable, Identifiable, Sendable {
    case topPicks, suggested, shortcuts, recentlyPlayed, madeForYou, artists, recentlyAdded, favorites, playlists, downloads, streaming
    var id: String { rawValue }
    var title: String {
        switch self {
        case .topPicks: "Top Picks"
        case .suggested: "Suggested for You"
        case .shortcuts: "Shortcuts"
        case .recentlyPlayed: "Recently Played"
        case .madeForYou: "Made for You"
        case .artists: "Artists"
        case .recentlyAdded: "Recently Added"
        case .favorites: "Favorite Songs"
        case .playlists: "Playlists"
        case .downloads: "On This iPhone"
        case .streaming: "From Your Server"
        }
    }
}

nonisolated struct HomeSectionConfig: Codable, Hashable, Identifiable, Sendable {
    var section: HomeSection
    var visible: Bool
    var id: String { section.rawValue }
}

nonisolated struct HomeShortcut: Codable, Hashable, Identifiable, Sendable {
    enum Action: String, Codable, CaseIterable, Identifiable, Sendable {
        case shuffleAll, smartShuffle, favorites, downloads, recentlyAdded, station, sleep30, audioLab, openEntry
        var id: String { rawValue }
        var title: String {
            switch self {
            case .shuffleAll: "Shuffle All"
            case .smartShuffle: "Smart Shuffle"
            case .favorites: "Play Favorites"
            case .downloads: "Play Downloads"
            case .recentlyAdded: "Recently Added"
            case .station: "Surprise Station"
            case .sleep30: "Sleep in 30 min"
            case .audioLab: "Sound"
            case .openEntry: "Open…"
            }
        }
        var icon: String {
            switch self {
            case .shuffleAll: "shuffle"
            case .smartShuffle: "sparkles"
            case .favorites: "star.fill"
            case .downloads: "arrow.down.circle.fill"
            case .recentlyAdded: "clock.badge.checkmark"
            case .station: "dot.radiowaves.left.and.right"
            case .sleep30: "moon.zzz.fill"
            case .audioLab: "slider.vertical.3"
            case .openEntry: "arrow.up.right.square"
            }
        }
    }
    var id = UUID()
    var action: Action
    var title: String
    var icon: String
    var entryKind: LibraryEntry.Kind?
    var entryKey: String?
}

@Observable
final class LayoutStore {
    static let shared = LayoutStore()

    var tabs: [TabItemConfig] { didSet { if !adoptingTheme { tabsCustomized = true }; save() } }
    var searchEnabled: Bool { didSet { if !adoptingTheme { tabsCustomized = true }; save() } }
    private(set) var tabsCustomized: Bool
    @ObservationIgnored private var adoptingTheme = false
    var homeSections: [HomeSectionConfig] { didSet { save() } }
    var shortcuts: [HomeShortcut] { didSet { save() } }

    static let defaultTabs = [TabItemConfig(kind: .home), TabItemConfig(kind: .library)]
    static let defaultSections: [HomeSectionConfig] = HomeSection.allCases.map {
        HomeSectionConfig(section: $0, visible: [.topPicks, .suggested, .recentlyPlayed, .madeForYou, .artists, .recentlyAdded].contains($0))
    }
    static let defaultShortcuts: [HomeShortcut] = [.shuffleAll, .favorites, .smartShuffle, .sleep30].map {
        HomeShortcut(action: $0, title: $0.title, icon: $0.icon)
    }

    private struct Stored: Codable {
        var tabs: [TabItemConfig]
        var searchEnabled: Bool
        var homeSections: [HomeSectionConfig]
        var shortcuts: [HomeShortcut]
        var tabsCustomized: Bool?
    }

    private init() {
        let s = UserDefaults.standard.data(forKey: "layout").flatMap { try? JSONDecoder().decode(Stored.self, from: $0) }
        let tabs = (s?.tabs.isEmpty == false ? s?.tabs : nil) ?? Self.defaultTabs
        let search = s?.searchEnabled ?? true
        self.tabs = tabs
        searchEnabled = search
        tabsCustomized = s?.tabsCustomized
            ?? !AppTheme.builtIns.contains { $0.tabs == tabs && ($0.searchTab ?? true) == search }
        var sections = s?.homeSections ?? Self.defaultSections
        for d in Self.defaultSections where !sections.contains(where: { $0.section == d.section }) {
            if d.section == .suggested {
                let at = sections.firstIndex { $0.section == .topPicks }.map { $0 + 1 } ?? 0
                sections.insert(HomeSectionConfig(section: .suggested, visible: true), at: at)
            } else {
                sections.append(HomeSectionConfig(section: d.section, visible: false))
            }
        }
        homeSections = sections
        shortcuts = s?.shortcuts ?? Self.defaultShortcuts
    }

    func adoptTabs(of theme: AppTheme) {
        guard !tabsCustomized, let themeTabs = theme.tabs, !themeTabs.isEmpty else { return }
        adoptingTheme = true
        defer { adoptingTheme = false }
        if tabs != themeTabs { tabs = themeTabs }
        if searchEnabled != (theme.searchTab ?? true) { searchEnabled = theme.searchTab ?? true }
    }

    var usesClassicBar: Bool { tabs.count == 2 && searchEnabled }
    var visibleSections: [HomeSection] { homeSections.filter(\.visible).map(\.section) }

    func resetTabs() {
        tabs = Self.defaultTabs
        searchEnabled = true
        tabsCustomized = false
        save()
    }
    func resetHome() { homeSections = Self.defaultSections; shortcuts = Self.defaultShortcuts }

    private func save() {
        let s = Stored(tabs: tabs, searchEnabled: searchEnabled, homeSections: homeSections, shortcuts: shortcuts, tabsCustomized: tabsCustomized)
        if let data = try? JSONEncoder().encode(s) { UserDefaults.standard.set(data, forKey: "layout") }
    }
}

// MARK: - Editors

struct CustomizeView: View {
    @Environment(LayoutStore.self) private var layout
    @Environment(PlayerModel.self) private var player
    @Environment(Router.self) private var router
    @Environment(AppSettings.self) private var settings
    @State private var editing: AppTheme?
    @State private var editingPlayer: AppTheme?

    var body: some View {
        @Bindable var settings = settings
        List {
            Section {
                NavigationLink { ThemesView() } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "paintpalette.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 32, height: 32)
                        Text("Themes")
                        Spacer()
                        Text(ThemeStore.shared.selected.name).foregroundStyle(.secondary)
                    }
                }
                Button {
                    let current = ThemeStore.shared.current
                    editing = current.builtIn ? ThemeStore.shared.duplicate(current) : current
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "paintbrush.pointed.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 32, height: 32)
                        Text("Colors, Fonts, Player & Lyrics")
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(.tertiary)
                    }
                }
                .tint(.primary)
            } footer: { Text("Colors, background, blur, transparency, glass, corner radius, fonts, icons, animations, player layout, album-art size, queue, mini player and lyrics are all part of a theme.") }

            Section {
                NavigationLink { StartupSettingsView() } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "scribble.variable")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 32, height: 32)
                        Text("Startup & App Icon")
                        Spacer()
                        Text(BrandStyle.current.name).foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                NavigationLink { TabsEditor() } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "dock.rectangle")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 32, height: 32)
                        Text("Tab Bar")
                        Spacer()
                        Text(layout.tabs.map(\.title).joined(separator: " | ")).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Button {
                    if player.current != nil {
                        router.editPlayerOnOpen = true
                        router.showSettings = false
                        Task { try? await Task.sleep(for: .milliseconds(450)); router.showPlayer = true }
                    } else {
                        let current = ThemeStore.shared.current
                        editingPlayer = current.builtIn ? ThemeStore.shared.duplicate(current) : current
                    }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "play.rectangle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 32, height: 32)
                        Text("Music Player")
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(.tertiary)
                    }
                }
                .tint(.primary)
                NavigationLink { WidgetCustomizer() } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 32, height: 32)
                        Text("Widgets")
                    }
                }
                NavigationLink { HomeEditor() } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "house.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 32, height: 32)
                        Text("Home Screen")
                    }
                }
            }

            Section("Lock Screen & Dynamic Island") {
                Toggle("Fullscreen Artwork", isOn: $settings.lockArtwork)
                if settings.lockArtwork {
                    Picker("Layout", selection: $settings.lockArtLayout) {
                        ForEach(LockArtLayout.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Motion", selection: $settings.lockArtMotion) {
                        ForEach(LockArtMotion.allCases) { Text($0.title).tag($0) }
                    }
                }
                Toggle("Live Lyrics", isOn: $settings.liveLyrics)
            } footer: {
                Text("Fullscreen Artwork makes a full-screen cover available. Tap the cover on the Lock Screen to expand it. Live Lyrics adds the current line as a Live Activity for songs with synced lyrics.")
            }
            .onChange(of: settings.lockArtwork) { player.refreshNowPlaying() }
            .onChange(of: settings.lockArtLayout) { player.refreshNowPlaying() }
            .onChange(of: settings.lockArtMotion) { player.refreshNowPlaying() }
            .onChange(of: settings.liveLyrics) { player.refreshNowPlaying() }
        }
        .navigationTitle("Customize")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { ThemeEditor(theme: $0) }
        .sheet(item: $editingPlayer) { PlayerLayoutSheet(theme: $0) }
    }
}

struct TabsEditor: View {
    @Environment(LayoutStore.self) private var layout
    @Environment(LibraryStore.self) private var library
    @State private var editing: TabItemConfig?

    private var available: [TabKind] {
        TabKind.allCases.filter { k in !layout.tabs.contains { $0.kind == k } }
    }

    var body: some View {
        @Bindable var layout = layout
        List {
            Section {
                ForEach(layout.tabs) { (tab: TabItemConfig) in
                    Button { editing = tab } label: {
                        HStack(spacing: 14) {
                            Image(systemName: tab.icon).frame(width: 28).foregroundStyle(Theme.accent)
                            Text(tab.title)
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                        }
                    }
                    .tint(.primary)
                    .deleteDisabled(layout.tabs.count <= 1)
                }
                .onMove { layout.tabs.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { if layout.tabs.count > 1 { layout.tabs.remove(atOffsets: $0) } }
                if layout.tabs.count < 5 {
                    Menu {
                        ForEach(available) { k in
                            Button { withAnimation { layout.tabs.append(TabItemConfig(kind: k)) } } label: { Label(k.title, systemImage: k.icon) }
                        }
                    } label: { Label("Add Tab", systemImage: "plus") }
                }
            } header: { Text("Tabs") } footer: { Text("Up to five tabs. Drag to reorder, swipe to remove, tap to rename or change the icon.") }

            Section {
                Toggle(isOn: $layout.searchEnabled.animation()) { Label("Search", systemImage: "magnifyingglass") }
            } footer: {
                Text("This layout uses the standard iOS tab bar with a separate search tab.")
            }

            Section { Button("Reset to Home | Library | Search") { withAnimation { layout.resetTabs() } } }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Tab Bar")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { (tab: TabItemConfig) in
            TabItemEditor(tab: tab) { updated in
                if let i = layout.tabs.firstIndex(where: { $0.id == updated.id }) { layout.tabs[i] = updated }
            }
        }
    }
}

struct TabItemEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var tab: TabItemConfig
    var save: (TabItemConfig) -> Void

    static let icons = ["house.fill", "sparkles", "dot.radiowaves.left.and.right", "music.note.list", "magnifyingglass",
                        "music.note", "square.stack", "music.mic", "music.quarternote.3", "arrow.down.circle",
                        "star", "heart", "list.bullet", "clock", "slider.vertical.3", "shippingbox",
                        "bolt", "headphones", "guitars", "pianokeys", "waveform", "flame", "moon.stars", "sun.max"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") { TextField("Name", text: $tab.title) }
                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 14) {
                        ForEach(Self.icons, id: \.self) { icon in
                            Button { tab.icon = icon } label: {
                                Image(systemName: icon)
                                    .font(.system(size: 20))
                                    .frame(width: 44, height: 44)
                                    .background(tab.icon == icon ? Theme.accent.opacity(0.2) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                                    .foregroundStyle(tab.icon == icon ? Theme.accent : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }
                Section { Button("Restore Default Name & Icon") { tab.title = tab.kind.title; tab.icon = tab.kind.icon } }
            }
            .navigationTitle("Edit Tab")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save(tab); dismiss() }.disabled(tab.title.isEmpty) }
            }
        }
    }
}

struct HomeEditor: View {
    @Environment(LayoutStore.self) private var layout

    var body: some View {
        @Bindable var layout = layout
        List {
            Section {
                ForEach($layout.homeSections) { $s in
                    Toggle(s.section.title, isOn: $s.visible)
                }
                .onMove { layout.homeSections.move(fromOffsets: $0, toOffset: $1) }
            } header: { Text("Sections") } footer: { Text("Drag to reorder, switch off what you don't need.") }

            Section {
                ForEach(layout.shortcuts) { s in
                    Label(s.title, systemImage: s.icon)
                }
                .onMove { layout.shortcuts.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { layout.shortcuts.remove(atOffsets: $0) }
                Menu {
                    ForEach(HomeShortcut.Action.allCases.filter { $0 != .openEntry }) { a in
                        Button { layout.shortcuts.append(HomeShortcut(action: a, title: a.title, icon: a.icon)) } label: { Label(a.title, systemImage: a.icon) }
                    }
                } label: { Label("Add Shortcut", systemImage: "plus") }
            } header: { Text("Shortcuts") } footer: { Text("Shown in the Shortcuts section on Home.") }

            Section { Button("Reset Home Screen") { withAnimation { layout.resetHome() } } }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Home Screen")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Downloads / offline

struct DownloadsView: View {
    enum Scope: String, CaseIterable, Identifiable { case all = "On This iPhone", downloaded = "Downloaded", streaming = "Not Downloaded"; var id: String { rawValue } }

    @Environment(LibraryStore.self) private var library
    @Environment(PlayerModel.self) private var player
    @Environment(DownloadManager.self) private var downloads
    @Environment(SourceManager.self) private var sources
    @State private var scope: Scope = .all
    @State private var confirmRemove = false
    @State private var editMode: EditMode = .inactive

    private var tracks: [Track] {
        let scope = scope
        _ = library.downloadOrder
        return library.memo("downloads|\(scope.rawValue)") {
            let list: [Track]
            switch scope {
            case .all: list = library.tracks.filter(\.isOffline)
            case .downloaded: list = library.tracks.filter(\.isDownloaded)
            case .streaming: list = library.tracks.filter { $0.isRemote && !$0.isDownloaded }
            }
            return library.orderedDownloads(SmartShuffle.libraryOrder(list))
        }
    }

    var body: some View {
        let list = tracks
        let running = downloads.runningIDs.compactMap { library.trackByID[$0] }.filter { downloads.state($0.id) != nil }
        let queued = downloads.queue.compactMap { library.trackByID[$0] }
        let failed = library.orderedDownloads(SmartShuffle.libraryOrder(downloads.states.compactMap { id, state in
            state.isFailed ? library.trackByID[id] : nil
        }))
        let canReorder = list.count > 1 || queued.count > 1
        List {
            if sources.hasSources || !ModuleStore.shared.modules.isEmpty {
                Picker("Show", selection: $scope) { ForEach(Scope.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)
            }
            if !running.isEmpty {
                Section("Downloading") {
                    ForEach(running) { t in
                        DownloadRow(track: t, state: downloads.state(t.id))
                    }
                }
            }
            if !queued.isEmpty {
                Section {
                    ForEach(queued) { t in
                        DownloadRow(track: t, state: downloads.state(t.id))
                    }
                    .onMove { from, to in
                        var ids = queued.map(\.id)
                        ids.move(fromOffsets: from, toOffset: to)
                        downloads.setQueueOrder(ids)
                    }
                    Button("Cancel Remaining", role: .destructive) { downloads.cancelAll() }
                } header: { Text("Waiting") } footer: {
                    Text("Downloads start from top to bottom.")
                }
            }
            if !failed.isEmpty {
                Section("Failed Downloads") {
                    ForEach(failed) { t in
                        DownloadRow(track: t, state: downloads.state(t.id))
                    }
                    Button("Retry Failed") { downloads.download(failed) }
                }
            }
            if !list.isEmpty {
                PlayShuffleBar(tracks: list, title: scope.rawValue)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                Section {
                    ForEach(list) { t in
                        TrackRow(track: t) { player.play(list, startAt: list.firstIndex(of: t) ?? 0, title: scope.rawValue) }
                    }
                    .onMove { from, to in
                        var ids = list.map(\.id)
                        ids.move(fromOffsets: from, toOffset: to)
                        library.setDownloadOrder(ids)
                    }
                } footer: {
                    Text("\(songCount(list.count)) · \(ByteCountFormatter.string(fromByteCount: size(list), countStyle: .file))")
                }
            }
        }
        .listStyle(.plain)
        .environment(\.editMode, $editMode)
        .navigationTitle("Downloads")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if list.isEmpty && downloads.states.isEmpty {
                ContentUnavailableView(scope == .streaming ? "Everything Is Downloaded" : "No Downloads",
                                       systemImage: "arrow.down.circle",
                                       description: Text("Long-press an album, playlist or artist from your server and choose Download."))
            }
        }
        .toolbar {
            if canReorder || editMode.isEditing {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editMode.isEditing ? "Done" : "Edit Order") {
                        withAnimation { editMode = editMode.isEditing ? .inactive : .active }
                    }
                }
            }
            if scope == .streaming, !list.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { downloads.download(list) } label: { Image(systemName: "arrow.down.circle") }.accessibilityLabel("Download All")
                }
            }
            if scope == .downloaded, !list.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) { confirmRemove = true } label: { Image(systemName: "trash") }.accessibilityLabel("Remove Downloads")
                }
            }
        }
        .confirmationDialog("Remove all downloaded songs from this iPhone? They stay in your library for streaming.", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove Downloads", role: .destructive) { downloads.removeDownloads(list) }
        }
    }

    private func size(_ list: [Track]) -> Int64 {
        list.reduce(0) { sum, t in
            guard !t.path.isEmpty else { return sum }
            return sum + ((try? FileManager.default.attributesOfItem(atPath: Paths.url(for: t).path)[.size] as? Int64) ?? 0)
        }
    }
}

struct DownloadRow: View {
    let track: Track
    let state: DownloadManager.State?
    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(track: track).thumbnail().frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title).font(.system(size: 15, weight: .medium)).lineLimit(1)
                switch state {
                case .downloading(let p): ProgressView(value: p).tint(Theme.accent)
                case .failed(let m): Text(m).font(.caption).foregroundStyle(.red).lineLimit(1)
                default: Text("Waiting…").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Favorites

struct FavoritesView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerModel.self) private var player

    var body: some View {
        let songs = library.memo("favorites.songs") {
            library.tracks.filter(\.isFavorite).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
        let entries = (library.playlistEntries + library.albumEntries + library.artistEntries).filter { library.isFavorite($0) }
        List {
            if !entries.isEmpty {
                Section("Collections") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(entries) { e in
                                NavigationLink(value: e.route) {
                                    VStack(spacing: 6) {
                                        ArtworkView(entry: e, radius: 12).thumbnail(340).frame(width: 110, height: 110)
                                        Text(e.title).font(.system(size: 13, weight: .medium)).lineLimit(1).frame(width: 110)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
            }
            if !songs.isEmpty {
                Section {
                    PlayShuffleBar(tracks: songs, title: "Favorites").listRowSeparator(.hidden)
                    ForEach(songs) { t in
                        TrackRow(track: t) { player.play(songs, startAt: songs.firstIndex(of: t) ?? 0, title: "Favorites") }
                    }
                } header: { Text("Songs") }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Favorites")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if songs.isEmpty && entries.isEmpty {
                ContentUnavailableView("No Favorites", systemImage: "star", description: Text("Star songs in the player, or long-press artists, albums and playlists."))
            }
        }
    }
}

// MARK: - Radio

struct RadioView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerModel.self) private var player
    @Environment(AppSettings.self) private var settings

    private var topArtists: [LibraryEntry] {
        library.memo("radio.topArtists") {
            library.artistEntries.sorted { a, b in
                a.tracks.reduce(0) { $0 + ($1.playCount ?? 0) } > b.tracks.reduce(0) { $0 + ($1.playCount ?? 0) }
            }.prefix(12).map { $0 }
        }
    }

    private var genres: [(String, [Track])] {
        library.memo("radio.genres") {
            Dictionary(grouping: library.tracks.filter { $0.genre != nil }, by: { $0.genre! })
                .filter { $0.value.count >= 5 }
                .sorted { $0.value.count > $1.value.count }
                .prefix(12).map { ($0.key, $0.value) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    station("Your Station", "Smart shuffle of everything", "sparkles", [.pink, .purple]) {
                        let list = SmartShuffle.order(library.tracks, options: .init(familiarity: max(0.6, settings.shuffleFamiliarity)))
                        player.play(list, title: "Your Station")
                    }
                    station("Discovery", "Songs you've never played", "binoculars.fill", [.teal, .blue]) {
                        let list = library.tracks.filter { ($0.playCount ?? 0) == 0 }.shuffled()
                        player.play(list.isEmpty ? library.tracks.shuffled() : list, title: "Discovery")
                    }
                    station("Favorites Radio", "Starred songs, shuffled", "star.fill", [.orange, .yellow]) {
                        player.play(library.tracks.filter(\.isFavorite), title: "Favorites Radio", shuffled: true)
                    }
                    station("Deep Cuts", "Rarely played album tracks", "opticaldisc.fill", [.indigo, .black]) {
                        let list = library.tracks.filter { ($0.playCount ?? 0) <= 1 && !$0.isFavorite }.shuffled()
                        player.play(Array(list.prefix(100)), title: "Deep Cuts")
                    }
                    if let t = player.current {
                        station("More Like This", t.title, "dot.radiowaves.left.and.right", [Theme.accent, .red]) { player.startStation(from: t) }
                    }
                    let upbeat = library.tracks.filter { ($0.bpm ?? 0) >= 118 }
                    if upbeat.count >= 10 {
                        station("Energy", "Fast songs, beat-matched", "bolt.fill", [.yellow, .red]) {
                            player.play(upbeat.sorted { ($0.bpm ?? 0) < ($1.bpm ?? 0) }, title: "Energy")
                        }
                    }
                    let calm = library.tracks.filter { ($0.bpm ?? 200) < 95 }
                    if calm.count >= 10 {
                        station("Calm", "Slow and easy", "leaf.fill", [.green, .teal]) { player.play(calm, title: "Calm", shuffled: true) }
                    }
                }
                .padding(.horizontal, 16)

                if !topArtists.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Artist Stations").font(.system(size: 22, weight: .bold)).padding(.horizontal, 20)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(topArtists) { a in
                                    Button { if let seed = a.tracks.randomElement() { player.startStation(from: seed) } } label: {
                                        VStack(spacing: 8) {
                                            ArtworkView(entry: a).thumbnail(370).frame(width: 120, height: 120)
                                                .overlay(alignment: .bottomTrailing) {
                                                    Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 13, weight: .bold))
                                                        .foregroundStyle(.white).frame(width: 32, height: 32).glassEffect(.regular, in: .circle)
                                                }
                                            Text(a.title).font(.system(size: 13, weight: .medium)).lineLimit(1).frame(width: 120)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }

                if !genres.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Genre Stations").font(.system(size: 22, weight: .bold)).padding(.horizontal, 20)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                            ForEach(genres, id: \.0) { g, list in
                                let c = placeholderColors(seed: g)
                                station(g, songCount(list.count), "music.note", [c.0, c.1]) {
                                    player.play(SmartShuffle.order(list, options: .init(familiarity: settings.shuffleFamiliarity)), title: "\(g) Radio")
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .padding(.vertical, 12)
        }
        .navigationTitle("Radio")
        .overlay { if library.tracks.isEmpty { ContentUnavailableView("No Music Yet", systemImage: "dot.radiowaves.left.and.right") } }
    }

    private func station(_ title: String, _ subtitle: String, _ icon: String, _ colors: [Color], action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon).font(.system(size: 22, weight: .semibold))
                Spacer(minLength: 8)
                Text(title).font(.system(size: 17, weight: .bold)).lineLimit(1)
                Text(subtitle).font(.system(size: 12)).opacity(0.8).lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
            .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 20 * ThemeStore.shared.current.cornerScale, style: .continuous))
        }
        .buttonStyle(PressScale())
        .sensoryFeedback(.impact(weight: .light), trigger: player.queueTitle)
    }
}

// MARK: - Recently played

struct RecentlyPlayedView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerModel.self) private var player

    var body: some View {
        let played = library.memo("recentlyPlayed") { library.tracks.filter { $0.lastPlayed != nil }.sorted { $0.lastPlayed! > $1.lastPlayed! } }
        let groups = Dictionary(grouping: played.prefix(300)) { Calendar.current.startOfDay(for: $0.lastPlayed!) }
        List {
            ForEach(groups.keys.sorted(by: >), id: \.self) { day in
                Section(dayTitle(day)) {
                    ForEach(groups[day]!) { t in
                        TrackRow(track: t) { player.play(played, startAt: played.firstIndex(of: t) ?? 0, title: "Recently Played") }
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Recently Played")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if played.isEmpty { ContentUnavailableView("Nothing Played Yet", systemImage: "clock") } }
    }

    private func dayTitle(_ d: Date) -> String {
        if Calendar.current.isDateInToday(d) { return "Today" }
        if Calendar.current.isDateInYesterday(d) { return "Yesterday" }
        return d.formatted(.dateTime.weekday(.wide).day().month())
    }
}

// MARK: - Sources (Jellyfin, Subsonic)

struct SourcesView: View {
    @Environment(SourceManager.self) private var sources
    @Environment(AppSettings.self) private var settings
    @Environment(Router.self) private var router
    @State private var adding: SourceKind?
    @State private var addingModule = false
    @State private var cacheSize: Int64 = 0
    @AppStorage("streamCacheMB") private var cacheMB = 1024

    var body: some View {
        @Bindable var sources = sources
        @Bindable var settings = settings
        List {
            Section {
                Button { router.openAddMusic() } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 32, height: 32)
                        Text("Add Music (Local, Jellyfin, Subsonic, etc.)")
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(.tertiary)
                    }
                }
                .tint(.primary)

                ForEach(sources.accounts) { acc in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 12) {
                            Image(systemName: acc.kind.symbol)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 36, height: 36)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(acc.name).font(.headline)
                                Text("\(acc.userName) · \(URL(string: acc.baseURL)?.host() ?? acc.baseURL)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if sources.syncing.contains(acc.id) { ProgressView() }
                        }
                        HStack {
                            Text("\(acc.trackCount) songs").font(.caption).foregroundStyle(.secondary)
                            if let d = acc.lastSync { Text("· synced \(d.formatted(.relative(presentation: .named)))").font(.caption).foregroundStyle(.secondary) }
                        }
                        if let e = sources.lastError[acc.id] { Text(e).font(.caption).foregroundStyle(.red) }
                    }
                    .swipeActions {
                        Button("Remove", role: .destructive) { sources.remove(acc.id) }
                        Button("Sync") { Task { await sources.sync(acc.id) } }.tint(.blue)
                    }
                    .contextMenu {
                        Button { Task { await sources.sync(acc.id) } } label: { Label("Sync Now", systemImage: "arrow.triangle.2.circlepath") }
                        Button { sources.setEnabled(acc.id, !acc.enabled) } label: { Label(acc.enabled ? "Pause Source" : "Resume Source", systemImage: acc.enabled ? "pause" : "play") }
                        Button(role: .destructive) { sources.remove(acc.id) } label: { Label("Remove Server", systemImage: "trash") }
                    }
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
