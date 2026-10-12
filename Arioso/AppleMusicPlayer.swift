import SwiftUI
import MediaPlayer
import AVKit

// MARK: - Apple Music style player
//
// Built fresh for Arioso. It is used whenever the active theme is the Apple Music one (inspiredBy == "Apple Music").
// Every other theme keeps using the customizable NowPlayingView.

struct AppleMusicPlayerView: View {
    enum Panel { case artwork, lyrics, queue }

    @Environment(PlayerModel.self) private var player
    @Environment(LibraryStore.self) private var library
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var panel: Panel = .artwork
    @State private var dragOffset: CGFloat = 0
    @State private var drift = false
    @State private var skipTick = 0
    @State private var showEQ = false
    @State private var showPicker = false
    @State private var editLyrics = false
    @State private var fullLyrics = false
    @Namespace private var ns

    private var screenHeight: CGFloat { UIScreen.main.bounds.height }

    var body: some View {
        let track = player.current
        ZStack {
            AMBackground(track: track, drift: drift)
                .contentShape(Rectangle())
                .gesture(dismissDrag)

            if let track {
                VStack(spacing: 0) {
                    Capsule()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: 38, height: 5)
                        .padding(.top, 8)
                        .padding(.bottom, 14)
                        .contentShape(Rectangle())
                        .onTapGesture { close() }
                        .gesture(dismissDrag)

                    if panel == .artwork {
                        artworkPanel(track)
                    } else {
                        headerRow(track)
                            .padding(.horizontal, 26)
                            .contentShape(Rectangle())
                            .gesture(dismissDrag)
                        if panel == .queue { queueHeader.padding(.horizontal, 26).padding(.top, 10) }
                        Group {
                            if panel == .lyrics {
                                LyricsView(track: track, edit: { editLyrics = true }, expand: { fullLyrics = true })
                            } else {
                                QueueView()
                            }
                        }
                        .frame(maxHeight: .infinity)
                        .padding(.horizontal, panel == .queue ? 10 : 18)
                        .padding(.top, 6)
                        .transition(.opacity)

                        scrubberBlock.padding(.horizontal, 26).padding(.top, 8)
                        transport.padding(.top, 6)
                    }

                    bottomRow
                        .padding(.horizontal, 26)
                        .padding(.top, 6)
                        .padding(.bottom, 10)
                }
                .animation(.smooth(duration: 0.5), value: panel)
                .sheet(isPresented: $showEQ) { EqualizerSheet() }
                .sheet(isPresented: $showPicker) { PlaylistPicker(trackIDs: [track.id]) }
                .sheet(isPresented: $editLyrics) { LyricsEditor(track: track) }
                .fullScreenCover(isPresented: $fullLyrics) { FullScreenLyricsView() }
            }
        }
        .environment(\.colorScheme, .dark)
        .mask { RoundedRectangle(cornerRadius: dragOffset > 0 ? min(44, 12 + dragOffset * 0.3) : 0, style: .continuous).ignoresSafeArea() }
        .scaleEffect(1 - min(dragOffset / screenHeight, 1) * 0.06, anchor: .top)
        .offset(y: dragOffset)
        .presentationBackground(.clear)
        .onAppear { drift = true }
        .onChange(of: track == nil) { _, gone in if gone { dismiss() } }
    }

    // MARK: Artwork panel

    @ViewBuilder private func artworkPanel(_ track: Track) -> some View {
        let playing = player.isPlaying
        ZStack {
            ArtworkView(track: track, radius: 14)
                .animatedCover()
                .aspectRatio(1, contentMode: .fit)
                .matchedGeometryEffect(id: "am-art", in: ns)
                .scaleEffect(playing ? 1 : 0.84)
                .shadow(color: Color.black.opacity(playing ? 0.5 : 0.22), radius: playing ? 30 : 10, y: playing ? 18 : 6)
                .animation(.spring(duration: 0.6, bounce: 0.3), value: playing)
                .id(track.id)
                .transition(.opacity.combined(with: .scale(scale: 0.94)))
        }
        .animation(.smooth(duration: 0.5), value: track.id)
        .padding(.horizontal, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(dismissDrag)

        VStack(spacing: 0) {
            headerRow(track)
                .contentShape(Rectangle())
                .gesture(dismissDrag)
            scrubberBlock.padding(.top, 18)
            transport.padding(.top, 10)
            volumeRow.padding(.top, 10)
        }
        .padding(.horizontal, 26)
    }

    // MARK: Title row

    private func headerRow(_ track: Track) -> some View {
        HStack(spacing: 12) {
            if panel != .artwork {
                ArtworkView(track: track, radius: 8)
                    .frame(width: 52, height: 52)
                    .matchedGeometryEffect(id: "am-art", in: ns)
            }
            VStack(alignment: .leading, spacing: 2) {
                MarqueeText(text: track.title, centered: false, centerShift: 0)
                    .font(.system(size: panel == .artwork ? 22 : 17, weight: .bold))
                MarqueeText(text: track.artist, centered: false, centerShift: 0)
                    .font(.system(size: panel == .artwork ? 20 : 15, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(track.id)
            .transition(.blurReplace)

            Button { library.toggleFavorite(track) } label: {
                Image(systemName: track.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.18)))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: track.isFavorite)
            }
            .buttonStyle(AMTransportStyle())
            .sensoryFeedback(.success, trigger: track.isFavorite)

            Menu {
                menuContent(track)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.18)))
            }
            .buttonStyle(AMTransportStyle())
        }
        .animation(.smooth(duration: 0.4), value: track.id)
    }

    @ViewBuilder private func menuContent(_ track: Track) -> some View {
        Button { showPicker = true } label: { Label("Add to a Playlist…", systemImage: "text.badge.plus") }
        Button {
            player.startStation(from: track)
            withAnimation(.smooth(duration: 0.45)) { panel = .queue }
        } label: { Label("Create Station", systemImage: "dot.radiowaves.left.and.right") }
        Divider()
        Button { router.open(.artist(track.artist)) } label: { Label("Go to Artist", systemImage: "music.mic") }
        Button { router.open(.album("\(track.artist)|\(track.album)")) } label: { Label("Go to Album", systemImage: "square.stack") }
        Divider()
        if let song = SharedSong(track) {
            ShareLink(item: song, preview: SharePreview(track.title)) { Label("Share Song", systemImage: "square.and.arrow.up") }
        } else {
            ShareLink(item: ShareItem.text(for: track), subject: Text(track.title)) { Label("Share Song", systemImage: "square.and.arrow.up") }
        }
        Button { editLyrics = true } label: { Label("Edit Lyrics", systemImage: "quote.bubble") }
        Button { showEQ = true } label: { Label("Equalizer", systemImage: "slider.vertical.3") }
        Menu {
            SleepTimerMenuItems()
        } label: { Label("Sleep Timer", systemImage: "moon.zzz") }
    }

    // MARK: Scrubber

    private var scrubberBlock: some View {
        AMScrubber()
    }

    // MARK: Transport

    private var transport: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Button {
                skipTick += 1
                player.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 34, weight: .regular))
                    .symbolEffect(.bounce.down, value: skipTick)
                    .frame(width: 76, height: 76)
            }
            .buttonStyle(AMTransportStyle())
            .sensoryFeedback(.impact(weight: .light), trigger: player.currentIndex)

            Spacer(minLength: 0)

            Button { player.togglePlay() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 46, weight: .regular))
                    .contentTransition(.symbolEffect(.replace.downUp))
                    .frame(width: 88, height: 88)
            }
            .buttonStyle(AMTransportStyle())
            .sensoryFeedback(.impact(weight: .medium), trigger: player.isPlaying)

            Spacer(minLength: 0)

            Button {
                skipTick += 1
                player.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 34, weight: .regular))
                    .symbolEffect(.bounce.up, value: skipTick)
                    .frame(width: 76, height: 76)
            }
            .buttonStyle(AMTransportStyle())
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 6)
    }

    // MARK: Volume

    private var volumeRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "speaker.fill").font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.6))
            AMVolumeSlider().frame(height: 34)
            Image(systemName: "speaker.wave.3.fill").font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.6))
        }
    }

    // MARK: Bottom row: lyrics · AirPlay · queue

    private var bottomRow: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            panelButton("quote.bubble", target: .lyrics, label: "Lyrics")
            Spacer(minLength: 0)
            AirPlayButton()
                .frame(width: 26, height: 26)
                .frame(width: 60, height: 44)
            Spacer(minLength: 0)
            panelButton("list.bullet", target: .queue, label: "Up Next")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
    }

    private func panelButton(_ symbol: String, target: Panel, label: String) -> some View {
        let on = panel == target
        return Button {
            withAnimation(.smooth(duration: 0.5)) { panel = on ? .artwork : target }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(on ? Color.black.opacity(0.8) : Color.white)
                .frame(width: 60, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(on ? 0.85 : 0))
                )
                .animation(.smooth(duration: 0.3), value: on)
        }
        .buttonStyle(AMTransportStyle())
        .accessibilityLabel(label)
        .sensoryFeedback(.selection, trigger: panel)
    }

    // MARK: Queue header (Playing Next · shuffle · repeat)

    private var queueHeader: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Playing Next").font(.system(size: 17, weight: .bold))
                if !player.queueTitle.isEmpty {
                    Text(player.queueTitle).font(.system(size: 13)).foregroundStyle(Color.white.opacity(0.55)).lineLimit(1)
                }
            }
            Spacer()
            pill("shuffle", on: player.shuffle) { player.setShuffle(!player.shuffle) }
            pill(player.repeatMode == .one ? "repeat.1" : "repeat", on: player.repeatMode != .off) { player.cycleRepeat() }
        }
    }

    private func pill(_ symbol: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(on ? Color.black.opacity(0.8) : Color.white)
                .frame(width: 40, height: 34)
                .background(Capsule().fill(on ? Color.white.opacity(0.88) : Color.white.opacity(0.18)))
                .contentTransition(.symbolEffect(.replace))
                .animation(.smooth(duration: 0.25), value: on)
        }
        .buttonStyle(AMTransportStyle())
        .sensoryFeedback(.selection, trigger: on)
    }

    // MARK: Dismiss

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { g in
                guard g.translation.height > 0 || dragOffset > 0 else { return }
                let y = max(0, g.translation.height)
                dragOffset = y < 40 ? y * 0.6 : y - 16
            }
            .onEnded { g in
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
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) { dismiss() }
        }
    }
}

// MARK: - Background

/// Blurred, slowly drifting artwork with the cover's colour washed over it, like Apple Music's moving backdrop.
private struct AMBackground: View {
    let track: Track?
    let drift: Bool

    var body: some View {
        let tint: Color = ArtworkCache.tint(for: track)
        ZStack {
            Color.black
            LinearGradient(colors: [tint, tint.opacity(0.55), Color.black], startPoint: .top, endPoint: .bottom)
            if let track {
                ArtworkView(track: track, radius: 0)
                    .scaledToFill()
                    .frame(width: 520, height: 520)
                    .blur(radius: 70)
                    .opacity(0.75)
                    .rotationEffect(.degrees(drift ? 14 : -14))
                    .offset(x: drift ? 40 : -40, y: drift ? -60 : 40)
                    .scaleEffect(drift ? 1.25 : 1.0)
                    .id(track.id)
                    .transition(.opacity)
                ArtworkView(track: track, radius: 0)
                    .scaledToFill()
                    .frame(width: 420, height: 420)
                    .blur(radius: 60)
                    .opacity(0.55)
                    .rotationEffect(.degrees(drift ? -20 : 20))
                    .offset(x: drift ? -70 : 60, y: drift ? 200 : 120)
                    .id("b-\(track.id)")
                    .transition(.opacity)
            }
            Color.black.opacity(0.28)
        }
        .animation(.easeInOut(duration: 16).repeatForever(autoreverses: true), value: drift)
        .animation(.easeInOut(duration: 0.9), value: track?.id)
        .clipped()
        .ignoresSafeArea()
    }
}

// MARK: - Scrubber

/// A thin bar that grows under your finger, with elapsed on the left and remaining on the right.
private struct AMScrubber: View {
    @Environment(PlayerModel.self) private var player
    @State private var dragging = false
    @State private var dragValue = 0.0

    var body: some View {
        let shown: Double = dragging ? dragValue : player.position
        let total: Double = player.duration
        let progress: Double = total > 0 ? min(1, max(0, shown / total)) : 0
        let remaining: Double = max(0, total - shown)
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(dragging ? 0.3 : 0.25))
                    Capsule().fill(Color.white.opacity(dragging ? 1 : 0.9))
                        .frame(width: max(0, geo.size.width * progress))
                }
                .frame(height: dragging ? 12 : 6)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { g in
                            dragging = true
                            let f: Double = min(1, max(0, Double(g.location.x / max(1, geo.size.width))))
                            dragValue = f * player.duration
                        }
                        .onEnded { _ in
                            player.seek(to: dragValue)
                            dragging = false
                        }
                )
                .animation(.spring(duration: 0.3, bounce: 0.35), value: dragging)
            }
            .frame(height: 22)

            HStack {
                Text(formatTime(shown)).contentTransition(.numericText())
                Spacer()
                Text("-" + formatTime(remaining))
            }
            .font(.system(size: 12, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(Color.white.opacity(dragging ? 0.85 : 0.55))
            .animation(.smooth(duration: 0.25), value: dragging)
        }
    }
}

// MARK: - Controls

/// Soft circular highlight and a springy squeeze, as on Apple Music's transport buttons.
private struct AMTransportStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Circle().fill(Color.white.opacity(configuration.isPressed ? 0.2 : 0)))
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(duration: 0.3, bounce: 0.45), value: configuration.isPressed)
    }
}

/// The system volume slider, tinted white.
private struct AMVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let v = MPVolumeView(frame: .zero)
        v.showsRouteButton = false
        return v
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {
        for sub in uiView.subviews {
            if let slider = sub as? UISlider {
                slider.minimumTrackTintColor = UIColor.white
                slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.28)
                slider.thumbTintColor = UIColor.white
            }
        }
    }
}
