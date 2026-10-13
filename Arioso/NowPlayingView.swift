import SwiftUI
import Translation

// MARK: - Full player

struct NowPlayingView: View {
    enum Mode { case artwork, lyrics, queue }

    @Environment(PlayerModel.self) private var player
    @Environment(LibraryStore.self) private var library
    @Environment(EQModel.self) private var eq
    @Environment(Router.self) private var router
    @Environment(DownloadManager.self) private var downloads
    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode = .artwork
    @State private var showEQ = false
    @State private var editLyrics = false
    @State private var showPicker = false
    @State private var showCover = false
    @State private var showMetadata = false
    @State private var dragOffset: CGFloat = 0
    @State private var fullLyrics = false
    @State private var sharing = false
    @State private var draft: AppTheme?
    @State private var editTarget: PlayerEditTarget?
    @State private var draggingID: String?
    @State private var wiggle = false
    @State private var showAllSettings = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var ns
    private var theme: AppTheme { draft ?? ThemeStore.shared.current }
    private var editing: Bool { draft != nil }
    private var cfg: PlayerConfig { theme.player }

    var body: some View {
        let track = player.current
        ZStack {
            background(track)
                .contentShape(Rectangle())
                .gesture(dismissDrag)
                .onTapGesture { if editing { withAnimation(.smooth(duration: 0.3)) { editTarget = editTarget == nil ? .screen : nil } } }
                .onLongPressGesture(minimumDuration: 0.45) { if !editing { enterEdit() } }
            if let track {
                VStack(spacing: cfg.spacing.gap) {
                    if mode == .artwork {
                        if editing { hiddenTray }
                        if !cfg.visibleBlocks.contains(.artwork) { Spacer(minLength: 0) }
                    } else {
                        titleRow(track, compact: true)
                            .contentShape(Rectangle())
                            .gesture(dismissDrag)
                        Group {
                            if mode == .lyrics { LyricsView(track: track, edit: { editLyrics = true }, expand: { fullLyrics = true }) } else { QueueView() }
                        }
                        .frame(maxHeight: .infinity)
                        .transition(.opacity)
                    }
                    let blocks = mode == .artwork ? cfg.visibleBlocks : cfg.visibleBlocks.filter { $0 != .artwork && $0 != .title }
                    ForEach(Array(blocks.enumerated()), id: \.element) { i, b in editable(b, index: i, track) }
                }
                .padding(.horizontal, 24)
                .padding(.top, editing ? 76 : 34)
                .padding(.bottom, 8 + cfg.spacing.bottomLift)
                .animation(.smooth(duration: 0.45), value: mode)
                .sheet(isPresented: $showEQ) { EqualizerSheet() }
                .sheet(isPresented: $editLyrics) { LyricsEditor(track: track) }
                .sheet(isPresented: $showPicker) { PlaylistPicker(trackIDs: [track.id]) }
                .sheet(isPresented: $showCover) { CoverDesigner(track: track) }
                .sheet(isPresented: $showMetadata) {
                    NavigationStack {
                        TrackEditor(track: library.trackByID[track.id] ?? track)
                            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showMetadata = false } } }
                    }
                }
                .fullScreenCover(isPresented: $fullLyrics) { FullScreenLyricsView() }
            }
            if editing { editToolbar } else { grabber }
            if editing, let target = editTarget {
                let bottomHalf: Bool = {
                    guard case .block(let b) = target, let i = cfg.visibleBlocks.firstIndex(of: b) else { return false }
                    return i >= cfg.visibleBlocks.count / 2
                }()
                VStack {
                    if !bottomHalf { Spacer() }
                    PlayerElementPanel(target: target, theme: draftBinding, close: { withAnimation(.smooth(duration: 0.3)) { editTarget = nil } },
                                       hide: hideAction(target))
                        .id(target)
                        .padding(.horizontal, 12)
                        .padding(.top, bottomHalf ? 58 : 0)
                        .padding(.bottom, bottomHalf ? 0 : 10)
                    if bottomHalf { Spacer() }
                }
                .transition(.move(edge: bottomHalf ? .top : .bottom).combined(with: .opacity))
                .zIndex(2)
            }
            if player.isBuffering {
                VStack { Spacer(); BufferingBadge().padding(.bottom, 250) }.allowsHitTesting(false)
            }
        }
        .environment(\.colorScheme, .dark)
        .mask { RoundedRectangle(cornerRadius: dragOffset > 0 ? min(44, 12 + dragOffset * 0.3) : 0, style: .continuous).ignoresSafeArea() }
        .scaleEffect(1 - min(dragOffset / screenHeight, 1) * 0.06, anchor: .top)
        .offset(y: dragOffset)
        .presentationBackground(.clear)
        .animation(.smooth(duration: 0.35), value: editing)
        .animation(.smooth(duration: 0.35), value: editTarget)
        .onDrop(of: [.text], isTargeted: nil) { _ in draggingID = nil; return true }
        .sheet(isPresented: $showAllSettings) {
            NavigationStack {
                PlayerLayoutEditor(theme: draftBinding)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showAllSettings = false } } }
            }
        }
        .onAppear {
            if router.editPlayerOnOpen { router.editPlayerOnOpen = false; enterEdit() }
        }
        .onChange(of: track == nil) { _, gone in if gone { dismiss() } }
    }

    // MARK: Pieces

    @ViewBuilder private func block(_ b: PlayerBlock, _ track: Track) -> some View {
        switch b {
        case .artwork:
            artwork(track).frame(maxHeight: .infinity).contentShape(Rectangle()).gesture(dismissDrag)
                .onLongPressGesture(minimumDuration: 0.45) { if !editing { enterEdit() } }
        case .title: titleRow(track, compact: false).contentShape(Rectangle()).gesture(dismissDrag)
        case .scrubber: ScrubberSection(showEQ: { showEQ = true }, showPreset: cfg.showEQBadge, showTimes: cfg.showTimes)
        case .controls: controls
        case .bar: bottomBar
        }
    }

    private func background(_ track: Track?) -> some View {
        let tint = ArtworkCache.tint(for: track)
        return ZStack {
            Color.black
            switch theme.nowPlaying {
            case .artworkTint:
                LinearGradient(colors: [tint, tint.opacity(0.6), .black], startPoint: .top, endPoint: .bottom)
            case .blurredArtwork:
                Color.clear
                    .overlay {
                        if let track {
                            ArtworkView(track: track, radius: 0)
                                .scaledToFill()
                                .blur(radius: 30 + theme.blur * 70)
                                .opacity(1 - theme.transparency * 0.5)
                                .id(track.id)
                                .transition(.opacity)
                        }
                    }
                    .clipped()
                LinearGradient(colors: [.black.opacity(0.15), .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
            case .themeColors:
                LinearGradient(colors: theme.colors, startPoint: .top, endPoint: .bottom)
                LinearGradient(colors: [tint.opacity(0.35 * (1 - theme.transparency)), .clear], startPoint: .top, endPoint: .center)
            case .black:
                EmptyView()
            }
            ThemeTexture(kind: theme.texture).environment(\.colorScheme, .dark)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.9), value: track?.id)
    }

    @ViewBuilder private func artwork(_ track: Track) -> some View {
        switch theme.playerLayout {
        case .classic:
            ArtworkView(track: track, radius: 20).animatedCover()
                .frame(maxHeight: min(380 * theme.artworkScale, UIScreen.main.bounds.height * 0.45))
                .matchedGeometryEffect(id: "art", in: ns)
                .scaleEffect(player.isPlaying ? 1 : 0.84)
                .shadow(color: .black.opacity(player.isPlaying ? 0.45 : 0.2), radius: player.isPlaying ? 28 : 10, y: player.isPlaying ? 16 : 6)
                .animation(.spring(duration: 0.55, bounce: 0.28), value: player.isPlaying)
                .id(track.id)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
        case .large:
            ArtworkView(track: track, radius: 12).animatedCover()
                .frame(maxHeight: min(470 * theme.artworkScale, UIScreen.main.bounds.height * 0.55))
                .matchedGeometryEffect(id: "art", in: ns)
                .scaleEffect(player.isPlaying ? 1 : 0.94)
                .shadow(color: .black.opacity(0.4), radius: 24, y: 14)
                .animation(.spring(duration: 0.55, bounce: 0.2), value: player.isPlaying)
                .id(track.id)
                .transition(.opacity)
                .padding(.horizontal, -8)
        case .vinyl:
            VinylArtwork(track: track, spinning: player.isPlaying)
                .frame(maxHeight: min(350 * theme.artworkScale, UIScreen.main.bounds.height * 0.42))
                .matchedGeometryEffect(id: "art", in: ns)
                .id(track.id)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
        case .minimal:
            VStack(spacing: 18) {
                ArtworkView(track: track, radius: 14)
                    .frame(width: 120 * theme.artworkScale, height: 120 * theme.artworkScale)
                    .matchedGeometryEffect(id: "art", in: ns)
                    .shadow(color: .black.opacity(0.35), radius: 14, y: 8)
                Image(systemName: "waveform")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .symbolEffect(.variableColor.iterative, isActive: player.isPlaying)
            }
            .id(track.id)
            .transition(.opacity)
        }
    }

    private func titleRow(_ track: Track, compact: Bool) -> some View {
        HStack(spacing: 12) {
            if compact {
                ArtworkView(track: track, radius: 9)
                    .frame(width: 54, height: 54)
                    .matchedGeometryEffect(id: "art", in: ns)
            }
            let centered = !compact && cfg.titleAlignment == .center
            let buttons = (cfg.showStar ? 1 : 0) + (cfg.showTitleMenu ? 1 : 0)
            let shift = buttons == 0 ? 0 : CGFloat(buttons * 42 + (buttons - 1) * 12 + 12) / 2
            VStack(alignment: centered ? .center : .leading, spacing: 2) {
                MarqueeText(text: track.title, centered: centered, centerShift: shift)
                    .font(.system(size: compact ? 17 : 22, weight: .bold))
                MarqueeText(text: track.artist, centered: centered, centerShift: shift)
                    .font(.system(size: compact ? 15 : 19))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
            .id(track.id)
            .transition(.blurReplace)
            if buttons > 0 { titleButtons(track) }
        }
        .animation(.smooth, value: track.id)
    }

    private func titleButtons(_ track: Track) -> some View {
        HStack(spacing: 12) {
            if cfg.showStar {
                AppleMusicStarButton(track: track, size: 17)
            }
            if cfg.showTitleMenu { moreMenu(track, size: 42) }
        }
    }

    private func moreMenu(_ track: Track, size: CGFloat) -> some View {
        Menu {
            ForEach(cfg.menu.filter(\.visible)) { entry in menuItem(entry.item, track) }
            Divider()
            Button { enterEdit() } label: { Label("Customize Player", systemImage: "slider.horizontal.below.square.and.square.filled") }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: size, height: size)
                .glassEffect(.regular.interactive(), in: .circle)
                .overlay { downloadRing(track) }
        }
        .buttonStyle(.plain)
    }

    private var screenHeight: CGFloat { UIScreen.main.bounds.height }

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { g in
                guard !editing, g.translation.height > 0 || dragOffset > 0 else { return }
                let y = max(0, g.translation.height)
                dragOffset = y < 40 ? y * 0.6 : y - 16
            }
            .onEnded { g in
                guard !editing else { return }
                let velocity = g.predictedEndTranslation.height - g.translation.height
                if g.translation.height > 120 || velocity > 260 { close(velocity: velocity) }
                else { withAnimation(.spring(duration: 0.4, bounce: 0.25)) { dragOffset = 0 } }
            }
    }

    private func close(velocity: CGFloat = 0) {
        let remaining = max(1, screenHeight - dragOffset)
        let speed = min(max(velocity / remaining, 0), 6)
        withAnimation(.interpolatingSpring(mass: 1, stiffness: 260, damping: 32, initialVelocity: speed)) {
            dragOffset = screenHeight + 40
        } completion: {
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { dismiss() }
        }
    }

    // MARK: Edit mode

    private var draftBinding: Binding<AppTheme> {
        Binding(get: { draft ?? ThemeStore.shared.current }, set: { draft = $0 })
    }

    private func enterEdit() {
        withAnimation(.smooth(duration: 0.35)) {
            mode = .artwork
            draft = ThemeStore.shared.current
            editTarget = nil
        }
        wiggle = true
    }

    private func finishEdit(save: Bool) {
        if save, var t = draft, t != ThemeStore.shared.current {
            if t.builtIn {
                let copy = ThemeStore.shared.duplicate(t)
                t.id = copy.id; t.name = copy.name; t.author = copy.author; t.builtIn = false
            }
            ThemeStore.shared.save(t)
            ThemeStore.shared.apply(t, edited: true)
        }
        withAnimation(.smooth(duration: 0.35)) { draft = nil; editTarget = nil }
        wiggle = false
    }

    private func hideAction(_ target: PlayerEditTarget) -> (() -> Void)? {
        guard case .block(let b) = target, b != .controls else { return nil }
        return {
            withAnimation(.smooth(duration: 0.35)) {
                if let i = draft?.player.blocks.firstIndex(where: { $0.block == b }) { draft?.player.blocks[i].visible = false }
                editTarget = nil
            }
        }
    }

    private var editToolbar: some View {
        VStack {
            HStack(spacing: 10) {
                Button("Cancel") { finishEdit(save: false) }
                    .buttonStyle(.glass)
                Spacer()
                Menu {
                    Section("Start From a Layout") {
                        ForEach(AppTheme.builtIns) { t in
                            Button(t.inspiredBy.map { "\(t.name) (\($0))" } ?? t.name) {
                                withAnimation(.smooth(duration: 0.45)) {
                                    draft?.player = t.player
                                    draft?.playerLayout = t.playerLayout
                                }
                            }
                        }
                    }
                    Button { showAllSettings = true } label: { Label(""…" Menu & All Settings", systemImage: "list.bullet") }
                } label: {
                    Label("Layouts", systemImage: "square.grid.2x2")
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 14).frame(height: 36)
                        .glassEffect(.regular.interactive(), in: Capsule())
                }
                .buttonStyle(.plain)
                Spacer()
                Button("Done") { finishEdit(save: true) }
                    .buttonStyle(.glassProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
            }
            .font(.system(size: 15, weight: .semibold))
            .padding(.horizontal, 16)
            .padding(.top, 6)
            Text(editTarget == nil ? "Drag to move · Tap to change · Tap the background for colors" : " ")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
        }
        .foregroundStyle(.white)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    @ViewBuilder private var hiddenTray: some View {
        let hidden = cfg.blocks.filter { !$0.visible }.map(\.block)
        if !hidden.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(hidden) { b in
                        Button {
                            withAnimation(.smooth(duration: 0.35)) {
                                if let i = draft?.player.blocks.firstIndex(where: { $0.block == b }) { draft?.player.blocks[i].visible = true }
                            }
                        } label: {
                            Label(b.title, systemImage: "plus")
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 12).frame(height: 32)
                                .glassEffect(.regular.interactive(), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollClipDisabled()
            .transition(.opacity)
        }
    }

    @ViewBuilder private func editable(_ b: PlayerBlock, index: Int, _ track: Track) -> some View {
        if editing {
            let selected = editTarget == .block(b)
            block(b, track)
                .allowsHitTesting(b == .bar)
                .padding(8)
                .background {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.white.opacity(selected ? 0.12 : 0.04))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(.white.opacity(selected ? 0.9 : 0.35), style: StrokeStyle(lineWidth: selected ? 2 : 1.2, dash: selected ? [] : [6, 5]))
                }
                .overlay(alignment: .topLeading) {
                    if b != .controls && b != .bar {
                        Button {
                            withAnimation(.smooth(duration: 0.35)) {
                                if let i = draft?.player.blocks.firstIndex(where: { $0.block == b }) { draft?.player.blocks[i].visible = false }
                                if editTarget == .block(b) { editTarget = nil }
                            }
                        } label: {
                            Image(systemName: "minus").font(.system(size: 12, weight: .heavy)).foregroundStyle(.black)
                                .frame(width: 24, height: 24).background(Circle().fill(.white))
                                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                        }
                        .buttonStyle(.plain)
                        .offset(x: -8, y: -8)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if b == .bar {
                        Button { withAnimation(.smooth(duration: 0.3)) { editTarget = .block(.bar) } } label: {
                            Image(systemName: "plus").font(.system(size: 12, weight: .heavy)).foregroundStyle(.black)
                                .frame(width: 24, height: 24).background(Circle().fill(.white))
                                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                        }
                        .buttonStyle(.plain)
                        .offset(x: 8, y: -8)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .onTapGesture { withAnimation(.smooth(duration: 0.3)) { editTarget = selected ? nil : .block(b) } }
                .onDrag {
                    draggingID = b.rawValue
                    return NSItemProvider(object: b.rawValue as NSString)
                }
                .onDrop(of: [.text], delegate: PlayerReorderDrop(target: b.rawValue, dragging: $draggingID) { from, to in moveBlock(from, to) })
                .rotationEffect(.degrees(wiggleAngle(index)))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.13 + Double(index % 3) * 0.02).repeatForever(autoreverses: true), value: wiggle)
                .sensoryFeedback(.selection, trigger: cfg.blocks)
        } else {
            block(b, track)
        }
    }

    private func wiggleAngle(_ i: Int) -> Double {
        guard editing, !reduceMotion else { return 0 }
        let a = i == 0 && cfg.visibleBlocks.first == .artwork ? 0.35 : 0.7
        return (wiggle ? a : -a) * (i.isMultiple(of: 2) ? 1 : -1)
    }

    private func moveBlock(_ from: String, _ to: String) {
        guard var blocks = draft?.player.blocks,
              let f = blocks.firstIndex(where: { $0.block.rawValue == from }),
              let t = blocks.firstIndex(where: { $0.block.rawValue == to }) else { return }
        blocks.move(fromOffsets: [f], toOffset: t > f ? t + 1 : t)
        draft?.player.blocks = blocks
    }

    private func moveBarItem(_ from: String, _ to: String) {
        guard var bar = draft?.player.bar,
              let f = bar.firstIndex(where: { $0.id.uuidString == from }),
              let t = bar.firstIndex(where: { $0.id.uuidString == to }) else { return }
        bar.move(fromOffsets: [f], toOffset: t > f ? t + 1 : t)
        draft?.player.bar = bar
    }

    private var grabber: some View {
        VStack {
            Button { close() } label: {
                Capsule().fill(.white.opacity(0.35)).frame(width: 40, height: 5).padding(.vertical, 12).padding(.horizontal, 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close Player")
            Spacer()
        }
        .padding(.top, 2)
    }

    @ViewBuilder private func menuItem(_ item: PlayerMenuItem, _ track: Track) -> some View {
        switch item {
        case .addToPlaylist:
            Button { showPicker = true } label: { Label("Add to Playlist…", systemImage: item.icon) }
        case .share:
            if let song = SharedSong(track) {
                ShareLink(item: song, preview: SharePreview(track.title)) { Label("Share Song", systemImage: item.icon) }
            } else {
                ShareLink(item: ShareItem.text(for: track), subject: Text(track.title)) { Label("Share Song", systemImage: item.icon) }
            }
        case .download: downloadItem(track)
        case .station:
            Button {
                player.startStation(from: track)
                withAnimation(.smooth(duration: 0.45)) { mode = .queue }
            } label: { Label("Create Station", systemImage: item.icon) }
        case .mix:
            if player.upcoming.first != nil {
                Button { player.mixNow() } label: { Label("Mix Into Next Song", systemImage: item.icon) }
            }
        case .goArtist:
            Button { router.open(.artist(track.artist)) } label: { Label("Go to Artist", systemImage: item.icon) }
        case .goAlbum:
            Button { router.open(.album("\(track.artist)|\(track.album)")) } label: { Label("Go to Album", systemImage: item.icon) }
        case .editMetadata:
            Button { showMetadata = true } label: { Label("Edit Metadata…", systemImage: item.icon) }
        case .designCover:
            Button { showCover = true } label: { Label("Design Cover…", systemImage: item.icon) }
        case .editLyrics:
            Button { editLyrics = true } label: { Label("Edit Lyrics", systemImage: item.icon) }
        case .saveQueue:
            Button {
                library.createPlaylist(name: player.queueTitle.isEmpty ? "Queue" : player.queueTitle, trackIDs: player.queue.map(\.trackID))
            } label: { Label("Save Queue as Playlist", systemImage: item.icon) }
        case .sleep:
            Menu { SleepTimerMenuItems() } label: { Label("Sleep Timer", systemImage: item.icon) }
        case .equalizer:
            Button { showEQ = true } label: { Label("Equalizer", systemImage: item.icon) }
        }
    }

    @ViewBuilder private func downloadItem(_ track: Track) -> some View {
        let t = library.trackByID[track.id] ?? track
        if t.isRemote {
            if t.isDownloaded {
                Button(role: .destructive) { downloads.removeDownloads([t]) } label: { Label("Remove Download", systemImage: "xmark.circle") }
            } else {
                switch downloads.state(t.id) {
                case .downloading(let p):
                    Button {} label: { Label("Downloading… \(Int(p * 100))%", systemImage: "arrow.down.circle.dotted") }.disabled(true)
                case .queued:
                    Button {} label: { Label("Waiting to Download…", systemImage: "arrow.down.circle.dotted") }.disabled(true)
                case .failed:
                    Button { downloads.download([t]) } label: { Label("Download Failed – Try Again", systemImage: "exclamationmark.arrow.circlepath") }
                case nil:
                    Button { downloads.download([t]) } label: { Label("Download Song", systemImage: "arrow.down.circle") }
                }
            }
        }
    }

    @ViewBuilder private func downloadRing(_ track: Track) -> some View {
        let t = library.trackByID[track.id] ?? track
        if t.isRemote {
            let phase = downloads.phase(t)
            ZStack {
                if phase.kind == 1 {
                    DownloadRing(fraction: phase.fraction, lineWidth: 2.5, tint: Theme.accent, track: .white.opacity(0.12))
                        .transition(.opacity.combined(with: .scale(scale: 1.15)))
                }
                if phase == .done || phase == .failed {
                    Image(systemName: phase == .done ? "arrow.down.circle.fill" : "exclamationmark.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white, phase == .done ? Theme.accent : .red)
                        .offset(x: 15, y: 15)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                }
            }
            .animation(.spring(duration: 0.45, bounce: 0.4), value: phase.kind)
            .sensoryFeedback(.success, trigger: phase.kind) { _, new in new == 2 }
            .allowsHitTesting(false)
        }
    }

    private var controls: some View {
        let c = cfg.controlScale
        return GlassEffectContainer(spacing: 18) {
            HStack(spacing: 0) {
                if cfg.showShuffleRepeat {
                    toggleIcon("shuffle", on: player.shuffle) { player.setShuffle(!player.shuffle) }
                    Spacer()
                }
                AppleMusicPreviousButton(size: 34 * c)
                Spacer()
                Button { player.togglePlay() } label: { playButton(c) }
                    .buttonStyle(PressScale())
                    .sensoryFeedback(.impact(weight: .medium), trigger: player.isPlaying)
                Spacer()
                AppleMusicNextButton(size: 34 * c)
                if cfg.showShuffleRepeat {
                    Spacer()
                    toggleIcon(player.repeatMode == .one ? "repeat.1" : "repeat", on: player.repeatMode != .off) { player.cycleRepeat() }
                }
            }
            .frame(maxWidth: cfg.showShuffleRepeat ? .infinity : 280 * c)
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder private func playButton(_ c: CGFloat) -> some View {
        let symbol = Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
        switch cfg.playStyle {
        case .glass:
            symbol.font(.system(size: 28 * c, weight: .bold)).foregroundStyle(.black.opacity(0.75))
                .frame(width: 74 * c, height: 74 * c)
                .contentTransition(.symbolEffect(.replace))
                .glassEffect(.regular.tint(.white.opacity(0.92)).interactive(), in: .circle)
        case .accent:
            symbol.font(.system(size: 28 * c, weight: .bold)).foregroundStyle(.white)
                .frame(width: 74 * c, height: 74 * c)
                .contentTransition(.symbolEffect(.replace))
                .glassEffect(.regular.tint(theme.accentColor).interactive(), in: .circle)
        case .plain:
            symbol.font(.system(size: 46 * c, weight: .bold))
                .frame(width: 74 * c, height: 74 * c)
                .contentTransition(.symbolEffect(.replace))
        }
    }

    private func toggleIcon(_ symbol: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                Circle().frame(width: 4, height: 4).opacity(on ? 1 : 0)
            }
            .foregroundStyle(on ? .white : .white.opacity(0.45))
            .frame(width: 44, height: 44)
            .animation(.smooth, value: on)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: on)
    }

    private var bottomBar: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                if !cfg.barHasFlexible { Spacer(minLength: 0) }
                ForEach(cfg.bar) { e in
                    if editing { editableBarItem(e) } else { barItem(e.item) }
                }
                if !cfg.barHasFlexible { Spacer(minLength: 0) }
            }
        }
        .foregroundStyle(.white)
    }

    private func editableBarItem(_ e: PlayerBarEntry) -> some View {
        Group {
            if e.item == .spacer {
                Capsule().strokeBorder(.white.opacity(0.45), style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                    .overlay { Image(systemName: "arrow.left.and.right").font(.system(size: 13, weight: .bold)).foregroundStyle(.white.opacity(0.6)) }
                    .frame(minWidth: 36, maxWidth: .infinity)
                    .frame(height: Self.barHeight)
            } else {
                barItem(e.item).allowsHitTesting(false)
            }
        }
        .overlay(alignment: .topLeading) {
            Button { withAnimation(.smooth(duration: 0.3)) { draft?.player.bar.removeAll { $0.id == e.id } } } label: {
                Image(systemName: "minus").font(.system(size: 10, weight: .heavy)).foregroundStyle(.black)
                    .frame(width: 20, height: 20).background(Circle().fill(.white))
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
            }
            .buttonStyle(.plain)
            .offset(x: -6, y: -6)
        }
        .contentShape(Rectangle())
        .onDrag {
            draggingID = e.id.uuidString
            return NSItemProvider(object: e.id.uuidString as NSString)
        }
        .onDrop(of: [.text], delegate: PlayerReorderDrop(target: e.id.uuidString, dragging: $draggingID) { from, to in moveBarItem(from, to) })
    }

    @ViewBuilder private func barItem(_ item: PlayerBarItem) -> some View {
        switch item {
        case .spacer:
            Spacer(minLength: 0)
        case .modes:
            PlayerModeSwitch(mode: $mode, height: Self.barHeight)
        case .lyrics, .queue:
            let target: Mode = item == .lyrics ? .lyrics : .queue
            Button { withAnimation(.smooth(duration: 0.45)) { mode = mode == target ? .artwork : target } } label: {
                bubble(item.icon, on: mode == target)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .sensoryFeedback(.selection, trigger: mode)
        case .sleep:
            Menu { SleepTimerMenuItems() } label: { bubble("moon.zzz", on: player.sleepActive) }
        case .airplay:
            AirPlayButton()
                .frame(width: 24, height: 24)
                .frame(width: Self.barHeight, height: Self.barHeight)
                .glassEffect(.regular.interactive(), in: .circle)
        case .equalizer:
            Button { showEQ = true } label: { bubble("slider.vertical.3", on: eq.enabled && !eq.isFlat) }
                .buttonStyle(.plain)
        case .favorite:
            if let track = player.current {
                AppleMusicStarButton(track: track, size: 17)
            }
        case .share:
            if let track = player.current {
                if let song = SharedSong(track) {
                    ShareLink(item: song, preview: SharePreview(track.title)) { bubble("square.and.arrow.up", on: false) }.buttonStyle(.plain)
                } else {
                    ShareLink(item: ShareItem.text(for: track), subject: Text(track.title)) { bubble("square.and.arrow.up", on: false) }.buttonStyle(.plain)
                }
            }
        case .more:
            if let track = player.current { moreMenu(track, size: Self.barHeight) }
        }
    }

    private static let barHeight: CGFloat = 48

    private func bubble(_ symbol: String, on: Bool) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(on ? .black : .white)
            .frame(width: Self.barHeight, height: Self.barHeight)
            .glassEffect(on ? .regular.tint(.white.opacity(0.92)).interactive() : .regular.interactive(), in: .circle)
            .animation(.smooth(duration: 0.3), value: on)
    }
}

private struct PlayerModeSwitch: View {
    @Binding var mode: NowPlayingView.Mode
    let height: CGFloat

    private static let modes: [(mode: NowPlayingView.Mode, symbol: String, title: String)] = [
        (.artwork, "music.note", "Artwork"), (.lyrics, "quote.bubble", "Lyrics"), (.queue, "list.bullet", "Queue")
    ]

    var body: some View {
        Picker("View", selection: Binding(get: { mode }, set: { m in withAnimation(.smooth(duration: 0.45)) { mode = m } })) {
            ForEach(Self.modes, id: \.mode) { m in
                Image(systemName: m.symbol).accessibilityLabel(m.title).tag(m.mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.large)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .sensoryFeedback(.selection, trigger: mode)
    }
}

struct PressScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(duration: 0.2, bounce: 0.3), value: configuration.isPressed)
    }
}
