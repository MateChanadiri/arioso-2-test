import SwiftUI

// MARK: - Links

enum Links {
    static let website = URL(string: "https://mrsc.pages.dev")!
    static let github = URL(string: "https://github.com/Henkek221/mrsc")!
}

// MARK: - Website look

enum Site {
    static let ink2 = dynamic(0x6E6E73, 0xA1A1A6)
    static let card = dynamic(0xFFFFFF, 0x2C2C2E)

    static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { @Sendable traits in
            traits.userInterfaceStyle == .dark ? UIColor(siteRGB: dark) : UIColor(siteRGB: light)
        })
    }
}

private extension UIColor {
    nonisolated convenience init(siteRGB v: UInt32) {
        self.init(red: CGFloat(v >> 16 & 0xFF) / 255, green: CGFloat(v >> 8 & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
}

extension View {
    func siteHeadline(_ size: CGFloat) -> some View {
        font(.system(size: size, weight: .bold)).tracking(-size * 0.04)
    }

    func siteLede(_ size: CGFloat = 18) -> some View {
        font(.system(size: size, weight: .medium)).tracking(-size * 0.016).foregroundStyle(Site.ink2)
    }
}

struct SiteNav<Trailing: View>: View {
    @AppStorage(BrandStyle.key) private var brand = BrandStyle.red.rawValue
    var onRed = false
    @ViewBuilder var trailing: Trailing

    var body: some View {
        let brandColor = (BrandStyle(rawValue: brand) ?? .red).color
        HStack(spacing: 9) {
            AppIconMark(color: onRed ? .white : brandColor, ink: onRed ? brandColor : .white)
                .frame(width: 28, height: 28)
            Text("Music")
                .foregroundStyle(onRed ? .white : .primary)
                .font(.system(size: 18, weight: .bold))
                .tracking(-0.36)
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 20)
        .frame(height: 54)
    }
}

struct AppIconMark: View {
    var color: Color = BrandStyle.current.color
    var ink: Color = .white

    var body: some View {
        GeometryReader { g in
            ZStack {
                RoundedRectangle(cornerRadius: g.size.width * 0.225, style: .continuous).fill(color)
                ForEach(BrushLetter.all.indices, id: \.self) { i in BrushLetter.all[i].fill(ink) }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

struct SitePill: View {
    let title: String
    var onRed = false
    let action: () -> Void
    init(_ title: String, onRed: Bool = false, action: @escaping () -> Void) {
        self.title = title; self.onRed = onRed; self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .tracking(-0.17)
                .foregroundStyle(onRed ? Theme.accent : .white)
                .frame(minWidth: 150)
                .padding(.horizontal, 12)
                .contentTransition(.opacity)
        }
        .buttonStyle(.glassProminent)
        .tint(onRed ? .white : Theme.accent)
        .controlSize(.extraLarge)
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.8), trigger: title)
    }
}

// MARK: - App Store look

enum PageTone {
    case paper, red, wine

    var colored: Bool { self != .paper }
    var ink: Color { colored ? .white : .primary }
    var lede: Color { colored ? .white.opacity(0.86) : Site.ink2 }

    @ViewBuilder var background: some View {
        switch self {
        case .paper: Color(uiColor: .systemBackground)
        case .red:
            ZStack {
                LinearGradient(colors: [Theme.accent.mix(with: .white, by: 0.08), Theme.accent, Theme.accent.mix(with: .black, by: 0.12)],
                               startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [.white.opacity(0.22), .clear], center: UnitPoint(x: 0.5, y: 0.6), startRadius: 0, endRadius: 360)
            }
        case .wine:
            ZStack {
                LinearGradient(colors: [Theme.accent.mix(with: .black, by: 0.32), Theme.accent.mix(with: .black, by: 0.58)],
                               startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [Theme.accent.opacity(0.45), .clear], center: UnitPoint(x: 0.5, y: 0.62), startRadius: 0, endRadius: 340)
            }
        }
    }
}

extension View {
    func heroHeadline(_ size: CGFloat) -> some View {
        font(.system(size: size, weight: .black)).tracking(-size * 0.045)
    }
}

// MARK: - Welcome

struct OnboardingView: View {
    @Environment(Router.self) private var router
    @Environment(LibraryStore.self) private var library
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("onboarded") private var onboarded = false

    private enum Stage { case hello, tour, sources }
    @State private var stage: Stage = .hello

    @State private var recordIn = false
    @State private var heroTitle = false
    @State private var heroLede = false
    @State private var ctaIn = false
    @State private var sourcesTitle = false
    @State private var sourcesLede = false
    @State private var rowsIn = false
    @State private var chosen: OnboardingSource?

    @State private var spin = SpinModel()
    @State private var dragAngle: Double?
    @State private var grab: (touch: Double, disc: Double, travelled: Double)?
    @State private var samples: [(t: Date, a: Double)] = []
    @State private var recordCenter: CGPoint = .zero
    @State private var tick = 0
    @State private var kick = 0

    var body: some View {
        ZStack {
            (stage == .hello ? PageTone.red : .paper).background
                .ignoresSafeArea()
                .animation(.smooth(duration: 0.5), value: stage)

            switch stage {
            case .hello:
                hero.transition(.opacity.combined(with: .offset(y: -40)))
            case .sources:
                sources.transition(.opacity.combined(with: .offset(y: 40)))
            case .tour:
                TourDeck(onFinish: { toSources() })
                    .transition(.move(edge: .bottom))
                    .zIndex(5)
            }
        }
        .sensoryFeedback(.selection, trigger: tick)
        .sensoryFeedback(.impact(weight: .medium), trigger: kick)
        .sensoryFeedback(.success, trigger: chosen) { _, now in now != nil }
        .task { await choreograph() }
    }

    // MARK: Hero

    private var hero: some View {
        GeometryReader { geo in
            let disc = min(geo.size.width * 0.66, 270, max(150, geo.size.height - 490))
            VStack(spacing: 0) {
                SiteNav(onRed: true) { laterButton(onRed: true).opacity(ctaIn ? 1 : 0) }

                Spacer(minLength: 8)
                record(size: disc)
                Spacer(minLength: 22)

                VStack(spacing: 0) {
                    Text("Free offline music player")
                        .font(.system(size: 17, weight: .bold))
                        .tracking(-0.25)
                        .foregroundStyle(.white.opacity(0.86))
                        .textRenderer(BlurReveal(progress: heroTitle ? 1 : 0))
                    Text("Sound. Your way.")
                        .heroHeadline(38)
                        .foregroundStyle(.white)
                        .textRenderer(BlurReveal(progress: heroTitle ? 1 : 0))
                        .padding(.top, 10)
                    Text("Plays the music you actually own. No ads. No account.")
                        .font(.system(size: 17, weight: .semibold))
                        .tracking(-0.27)
                        .foregroundStyle(.white.opacity(0.86))
                        .textRenderer(BlurReveal(progress: heroLede ? 1 : 0))
                        .padding(.top, 16)
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 26)

                Spacer(minLength: 22)

                VStack(spacing: 18) {
                    SitePill("Play my music", onRed: true) { start() }
                    Button { showTour() } label: {
                        HStack(spacing: 5) {
                            Text("See what it can do")
                            Image(systemName: "chevron.right").font(.system(size: 14, weight: .bold))
                        }
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(height: 30)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .opacity(ctaIn ? 1 : 0)
                .offset(y: ctaIn ? 0 : 24)
                .blur(radius: ctaIn ? 0 : 6)
                .padding(.bottom, 12)
            }
        }
    }

    private func laterButton(onRed: Bool = false) -> some View {
        Button("Later") { finish {} }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(onRed ? .white.opacity(0.8) : Site.ink2)
    }

    private func record(size: CGFloat) -> some View {
        return TimelineView(.animation(paused: reduceMotion && dragAngle == nil)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let angle = dragAngle ?? spin.angle(at: ctx.date)
            let float = reduceMotion ? 0 : 3 * (1 - cos(t * .pi / 3))
            ZStack {
                Circle()
                    .fill(Color(red: 0.35, green: 0, blue: 0.08))
                    .frame(width: size * 0.78, height: size * 0.78)
                    .blur(radius: size * 0.16)
                    .offset(y: size * 0.16)
                    .opacity(recordIn ? 0.55 : 0)
                VinylDisc(angle: .degrees(angle), label: chosen?.color ?? Theme.accent, symbol: chosen?.symbol, light: false)
                    .frame(width: size, height: size)
            }
            .offset(y: -float)
        }
        .frame(width: size, height: size)
        .offset(y: recordIn || reduceMotion ? 0 : 460)
        .contentShape(Circle())
        .onGeometryChange(for: CGPoint.self) { p in
            let f = p.frame(in: .global)
            return CGPoint(x: f.midX, y: f.midY)
        } action: { recordCenter = $0 }
        .gesture(spinGesture)
        .accessibilityHidden(true)
    }

    private var spinGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { v in
                let a = atan2(v.location.y - recordCenter.y, v.location.x - recordCenter.x) * 180 / .pi
                let now = Date()
                if grab == nil {
                    grab = (a, spin.angle(at: now), 0)
                    samples = []
                }
                guard var g = grab else { return }
                var delta = a - g.touch
                while delta > 180 { delta -= 360 }
                while delta < -180 { delta += 360 }
                g.touch = a
                g.disc += delta
                let before = Int(g.travelled / 24)
                g.travelled += abs(delta)
                if Int(g.travelled / 24) != before { tick += 1 }
                grab = g
                dragAngle = g.disc
                samples.append((now, g.disc))
                samples.removeAll { now.timeIntervalSince($0.t) > 0.1 }
            }
            .onEnded { _ in
                let now = Date()
                var velocity = 0.0
                if let first = samples.first, let last = samples.last, last.t > first.t {
                    velocity = (last.a - first.a) / last.t.timeIntervalSince(first.t)
                }
                spin.reset(at: now, angle: dragAngle ?? spin.angle(at: now), velocity: max(-1800, min(1800, velocity)))
                dragAngle = nil
                grab = nil
            }
    }

    // MARK: Sources

    private var sources: some View {
        GeometryReader { geo in
            let disc = min(geo.size.width * 0.42, 170, max(110, geo.size.height - 560))
            VStack(spacing: 0) {
                SiteNav { laterButton().opacity(chosen == nil ? 1 : 0) }

                Spacer(minLength: 8)
                record(size: disc)
                Spacer(minLength: 20)

                VStack(spacing: 12) {
                    Text("Where's your music?")
                        .heroHeadline(36)
                        .textRenderer(BlurReveal(progress: sourcesTitle ? 1 : 0))
                    Text(chosen == nil ? "Pick one. You can add the rest later." : "Nice. Getting it ready…")
                        .siteLede(17)
                        .contentTransition(.opacity)
                        .textRenderer(BlurReveal(progress: sourcesLede ? 1 : 0))
                }
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)

                Spacer(minLength: 20)

                VStack(spacing: 10) {
                    ForEach(Array(OnboardingSource.allCases.enumerated()), id: \.element) { i, source in
                        sourceRow(source, index: i)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
    }

    private func sourceRow(_ source: OnboardingSource, index i: Int) -> some View {
        let isChosen = chosen == source
        let other = chosen != nil && !isChosen
        return Button { choose(source) } label: {
            HStack(spacing: 14) {
                Image(systemName: source.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(source.color.gradient, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(source.title)
                        .font(.system(size: 17, weight: .semibold))
                        .tracking(-0.3)
                        .foregroundStyle(.primary)
                    Text(source.detail)
                        .font(.system(size: 14))
                        .foregroundStyle(Site.ink2)
                }
                Spacer(minLength: 8)
                Image(systemName: isChosen ? "checkmark" : "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(isChosen ? Theme.accent : Site.ink2)
            }
            .padding(.horizontal, 14)
            .frame(height: 66)
            .background(Site.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(isChosen ? 0.12 : 0.05), radius: isChosen ? 14 : 8, y: isChosen ? 6 : 3)
            .scaleEffect(isChosen ? 1.02 : 1)
            .opacity(other ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .opacity(rowsIn ? 1 : 0)
        .offset(y: rowsIn ? 0 : 16)
        .animation(.smooth(duration: 0.45).delay(Double(i) * 0.07), value: rowsIn)
        .animation(.spring(duration: 0.45, bounce: 0.3), value: chosen)
    }

    // MARK: Flow

    private func start() {
        finish {
            router.showOnboarding = false
            onboarded = true
        }
    }

    private func showTour() {
        kick += 1
        withAnimation(.smooth(duration: 0.5)) { stage = .tour }
    }

    private func toSources() {
        withAnimation(.smooth(duration: 0.5)) { stage = .sources }
        Task { await choreographSources() }
    }

    private func choose(_ source: OnboardingSource) {
        chosen = source
        Task {
            try? await Task.sleep(for: .seconds(1.1))
            finish {
                switch source {
                case .local: router.openAddMusic()
                case .server: router.showSettings = true
                }
            }
        }
    }

    private func finish(_ action: @escaping () -> Void) {
        onboarded = true
        withAnimation(.smooth(duration: 0.45)) {
            router.showOnboarding = false
        }
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            action()
        }
    }

    // MARK: Choreography

    private func choreograph() async {
        guard !reduceMotion else {
            recordIn = true; heroTitle = true; heroLede = true; ctaIn = true
            return
        }
        try? await Task.sleep(for: .milliseconds(250))
        withAnimation(.spring(duration: 0.9, bounce: 0.35)) { recordIn = true }
        try? await Task.sleep(for: .milliseconds(450))
        withAnimation(.smooth(duration: 0.7)) { heroTitle = true }
        try? await Task.sleep(for: .milliseconds(250))
        withAnimation(.smooth(duration: 0.7)) { heroLede = true }
        try? await Task.sleep(for: .milliseconds(350))
        withAnimation(.smooth(duration: 0.6)) { ctaIn = true }
    }

    private func choreographSources() async {
        guard !reduceMotion else {
            sourcesTitle = true; sourcesLede = true; rowsIn = true
            return
        }
        try? await Task.sleep(for: .milliseconds(300))
        withAnimation(.smooth(duration: 0.7)) { sourcesTitle = true }
        try? await Task.sleep(for: .milliseconds(250))
        withAnimation(.smooth(duration: 0.7)) { sourcesLede = true }
        try? await Task.sleep(for: .milliseconds(300))
        withAnimation(.smooth(duration: 0.5)) { rowsIn = true }
    }
}

// MARK: - Onboarding sources

enum OnboardingSource: String, CaseIterable {
    case local, server

    var title: String {
        switch self {
        case .local: "Songs on my iPhone"
        case .server: "Jellyfin · Subsonic"
        }
    }

    var detail: String {
        switch self {
        case .local: "Import files from the Files app, AirDrop, or other apps."
        case .server: "Stream from your own server. Subsonic, Navidrome, Jellyfin and more."
        }
    }

    var symbol: String {
        switch self {
        case .local: "iphone"
        case .server: "server.rack"
        }
    }

    var color: Color {
        switch self {
        case .local: Theme.accent
        case .server: .indigo
        }
    }
}

// MARK: - Tour

struct TourDeck: View {
    let onFinish: () -> Void
    @State private var index = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let pages: [(title: String, lede: String, symbol: String, colors: [Color])] = [
        ("Customize everything.", "Change fonts, colors, layouts, animations — make it yours.", "paintpalette.fill", [.pink, .purple]),
        ("Lyrics that move.", "Word-by-word karaoke, synced to your songs, translated on device.", "quote.bubble.fill", [.orange, .red]),
        ("Your library, organized.", "Smart playlists, auto-tagging, and analysis that actually helps.", "square.stack.3d.up.fill", [.teal, .blue]),
        ("No ads. No account.", "Free and open source. Your music stays on your device.", "lock.shield.fill", [.green, .mint])
    ]

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)

            ZStack {
                ForEach(Array(pages.enumerated()), id: \.offset) { i, page in
                    if i == index {
                        tourCard(page)
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                            .id(i)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)

            Spacer(minLength: 20)

            HStack(spacing: 8) {
                ForEach(pages.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == index ? Theme.accent : Color.white.opacity(0.3))
                        .frame(width: i == index ? 24 : 8, height: 8)
                        .animation(.smooth(duration: 0.35), value: index)
                }
            }
            .padding(.bottom, 16)

            HStack(spacing: 14) {
                if index > 0 {
                    Button {
                        withAnimation(.smooth(duration: 0.45)) { index -= 1 }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button {
                    if index < pages.count - 1 {
                        withAnimation(.smooth(duration: 0.45)) { index += 1 }
                    } else {
                        onFinish()
                    }
                } label: {
                    Text(index < pages.count - 1 ? "Next" : "Get Started")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(minWidth: 120)
                        .padding(.horizontal, 12)
                }
                .buttonStyle(.glassProminent)
                .tint(.white)
                Spacer()
                if index < pages.count - 1 {
                    Button {
                        withAnimation(.smooth(duration: 0.45)) { index = pages.count - 1 }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear.frame(width: 44, height: 44)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
    }

    private func tourCard(_ page: (title: String, lede: String, symbol: String, colors: [Color])) -> some View {
        VStack(spacing: 22) {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(LinearGradient(colors: page.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 180, height: 180)
                    .shadow(color: page.colors[0].opacity(0.4), radius: 24, y: 12)
                Image(systemName: page.symbol)
                    .font(.system(size: 72, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 10) {
                Text(page.title)
                    .heroHeadline(30)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                Text(page.lede)
                    .siteLede(17)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
        }
        .padding(.vertical, 24)
    }
}

// MARK: - Vinyl disc

struct VinylDisc: View {
    let angle: Angle
    let label: Color
    let symbol: String?
    var side: String? = nil
    var light: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(white: light ? 0.12 : 0.06))
                .shadow(color: .black.opacity(0.4), radius: 24, y: 12)

            ForEach(0..<8) { i in
                Circle()
                    .stroke(Color.white.opacity(0.04), lineWidth: 0.8)
                    .padding(CGFloat(12 + i * 10))
            }

            Circle()
                .fill(label.gradient)
                .padding(58)
                .shadow(color: label.opacity(0.4), radius: 12, y: 4)

            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
            } else if let side {
                Text(side)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
            }

            Circle()
                .fill(Color(white: 0.08))
                .frame(width: 14, height: 14)
        }
        .aspectRatio(1, contentMode: .fit)
        .rotationEffect(angle)
        .animation(.easeOut(duration: 0.45), value: label)
        .animation(.spring(duration: 0.5, bounce: 0.3), value: symbol)
    }
}

// MARK: - Spin model

struct SpinModel {
    private var base = 0.0
    private var anchor = Date()
    private var v0 = 0.0
    var idle = 22.0
    var friction = 1.5

    func angle(at t: Date) -> Double {
        let dt = max(0, t.timeIntervalSince(anchor))
        return base + idle * dt + (v0 - idle) * (1 - exp(-friction * dt)) / friction
    }

    mutating func reset(at t: Date, angle: Double, velocity: Double) {
        base = angle
        anchor = t
        v0 = velocity
    }
}

// MARK: - Text reveal

struct BlurReveal: TextRenderer, Animatable {
    var progress: Double
    var spread = 0.55

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        var glyphs: [Text.Layout.RunSlice] = []
        for line in layout { for run in line { for slice in run { glyphs.append(slice) } } }
        let count = Double(max(1, glyphs.count))
        for (i, glyph) in glyphs.enumerated() {
            let start = Double(i) / count * spread
            let local = min(1, max(0, (progress - start) / (1 - spread)))
            let e = 1 - pow(1 - local, 3)
            var c = ctx
            c.opacity = e
            if e < 1 { c.addFilter(.blur(radius: (1 - e) * 7)) }
            c.translateBy(x: 0, y: (1 - e) * 9)
            c.draw(glyph)
        }
    }
}

// MARK: - Buttons

struct GlassCTA: View {
    let title: String
    var onRed = false
    let action: () -> Void
    init(_ title: String, onRed: Bool = false, action: @escaping () -> Void) {
        self.title = title; self.onRed = onRed; self.action = action
    }

    var body: some View {
        Group {
            if onRed {
                Button(action: action) { label.foregroundStyle(Theme.accent) }.buttonStyle(.glassProminent).tint(.white)
            } else {
                Button(action: action) { label }.buttonStyle(.glassProminent).tint(Theme.accent)
            }
        }
        .controlSize(.extraLarge)
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.8), trigger: title)
    }

    private var label: some View {
        Text(title)
            .font(.system(size: 17, weight: .bold))
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .contentTransition(.opacity)
    }
}

struct PrimaryPill: View {
    let title: String
    let action: () -> Void
    init(_ title: String, action: @escaping () -> Void) { self.title = title; self.action = action }

    var body: some View {
        GlassCTA(title, action: action)
    }
}

// MARK: - Goodbye

struct GoodbyeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var spin: SpinModel = {
        var m = SpinModel()
        m.idle = 0
        m.friction = 0.5
        return m
    }()
    @State private var titleIn = false
    @State private var subtitleIn = false
    @State private var stayed = false
    @State private var kick = 0

    var body: some View {
        VStack(spacing: 0) {
            TimelineView(.animation(paused: reduceMotion)) { ctx in
                VinylDisc(angle: .degrees(spin.angle(at: ctx.date)), label: Theme.accent, symbol: nil,
                          side: stayed ? "SIDE A · 33⅓" : "THE END", light: scheme == .light)
            }
            .frame(width: 200, height: 200)
            .padding(.top, 40)

            VStack(spacing: 10) {
                Text(stayed ? "Glad you're staying." : "Goodbye — see you soon.")
                    .font(.system(size: 28, weight: .semibold))
                    .tracking(-0.5)
                    .textRenderer(BlurReveal(progress: titleIn ? 1 : 0))
                    .id(stayed)
                    .transition(.opacity)
                Text("Thanks for listening. Removing Music also removes the music you imported into it — your original files and your server stay as they are.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .textRenderer(BlurReveal(progress: subtitleIn ? 1 : 0))
            }
            .multilineTextAlignment(.center)
            .padding(.top, 28)

            Spacer(minLength: 20)
            PrimaryPill("Keep Listening") { stay() }
                .disabled(stayed)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 16)
        .background { ThemeBackgroundView() }
        .presentationDetents([.fraction(0.68)])
        .presentationDragIndicator(.visible)
        .sensoryFeedback(.impact(weight: .medium), trigger: kick)
        .task {
            spin.reset(at: .now, angle: 0, velocity: reduceMotion ? 0 : 240)
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 250))
            withAnimation(.linear(duration: reduceMotion ? 0 : 1.0)) { titleIn = true }
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 300))
            withAnimation(.linear(duration: reduceMotion ? 0 : 1.4)) { subtitleIn = true }
        }
    }

    private func stay() {
        kick += 1
        let now = Date()
        let angle = spin.angle(at: now)
        spin.idle = 22
        spin.friction = 1.5
        spin.reset(at: now, angle: angle, velocity: reduceMotion ? 0 : 720)
        withAnimation(.smooth(duration: 0.4)) { stayed = true }
        Task {
            try? await Task.sleep(for: .milliseconds(1100))
            dismiss()
        }
    }
}
