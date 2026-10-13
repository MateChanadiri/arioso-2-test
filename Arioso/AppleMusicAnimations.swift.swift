import SwiftUI

// MARK: - Apple Music Next Button (Flowing Triangles)
struct AppleMusicNextButton: View {
    @Environment(PlayerModel.self) private var player
    let size: CGFloat
    
    enum AnimationPhase: CaseIterable { case idle, animating }
    
    var body: some View {
        Button { player.next() } label: {
            PhaseAnimator(AnimationPhase.allCases, trigger: player.currentIndex) { phase in
                ZStack {
                    let gap = size * 0.18
                    let triW = size * 0.35
                    let triH = size * 0.5
                    
                    Image(systemName: "triangle.fill")
                        .resizable().aspectRatio(contentMode: .fit)
                        .frame(width: triW, height: triH)
                        .offset(x: phase == .animating ? gap * 2.5 : gap)
                        .opacity(phase == .animating ? 0 : 1)
                        .scaleEffect(phase == .animating ? 0.4 : 1)
                    
                    Image(systemName: "triangle.fill")
                        .resizable().aspectRatio(contentMode: .fit)
                        .frame(width: triW, height: triH)
                        .offset(x: phase == .animating ? gap : -gap)
                    
                    Image(systemName: "triangle.fill")
                        .resizable().aspectRatio(contentMode: .fit)
                        .frame(width: triW, height: triH)
                        .offset(x: phase == .animating ? -gap : -gap * 2.5)
                        .opacity(phase == .animating ? 1 : 0)
                        .scaleEffect(phase == .animating ? 1 : 0.4)
                }
                .frame(width: size, height: size)
            } animation: { phase in
                switch phase {
                case .idle: .easeOut(duration: 0.15)
                case .animating: .spring(response: 0.35, dampingFraction: 0.65, blendDuration: 0)
                }
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: player.currentIndex)
    }
}

// MARK: - Apple Music Previous Button (Reverse Flow)
struct AppleMusicPreviousButton: View {
    @Environment(PlayerModel.self) private var player
    let size: CGFloat
    
    enum AnimationPhase: CaseIterable { case idle, animating }
    
    var body: some View {
        Button { player.previous() } label: {
            PhaseAnimator(AnimationPhase.allCases, trigger: player.currentIndex) { phase in
                ZStack {
                    let gap = size * 0.18
                    let triW = size * 0.35
                    let triH = size * 0.5
                    
                    Image(systemName: "triangle.fill")
                        .resizable().aspectRatio(contentMode: .fit)
                        .frame(width: triW, height: triH)
                        .rotationEffect(.degrees(180))
                        .offset(x: phase == .animating ? -gap * 2.5 : -gap)
                        .opacity(phase == .animating ? 0 : 1)
                        .scaleEffect(phase == .animating ? 0.4 : 1)
                    
                    Image(systemName: "triangle.fill")
                        .resizable().aspectRatio(contentMode: .fit)
                        .frame(width: triW, height: triH)
                        .rotationEffect(.degrees(180))
                        .offset(x: phase == .animating ? -gap : gap)
                    
                    Image(systemName: "triangle.fill")
                        .resizable().aspectRatio(contentMode: .fit)
                        .frame(width: triW, height: triH)
                        .rotationEffect(.degrees(180))
                        .offset(x: phase == .animating ? gap : gap * 2.5)
                        .opacity(phase == .animating ? 1 : 0)
                        .scaleEffect(phase == .animating ? 1 : 0.4)
                }
                .frame(width: size, height: size)
            } animation: { phase in
                switch phase {
                case .idle: .easeOut(duration: 0.15)
                case .animating: .spring(response: 0.35, dampingFraction: 0.65, blendDuration: 0)
                }
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: player.currentIndex)
    }
}

// MARK: - Apple Music Star Button (Pop & Fill)
struct AppleMusicStarButton: View {
    @Environment(LibraryStore.self) private var library
    let track: Track
    let size: CGFloat
    
    enum StarPhase: CaseIterable { case idle, popping }
    
    var body: some View {
        Button { library.toggleFavorite(track) } label: {
            PhaseAnimator(StarPhase.allCases, trigger: track.isFavorite) { phase in
                Image(systemName: track.isFavorite ? "star.fill" : "star")
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(track.isFavorite ? .yellow : .white)
                    .scaleEffect(phase == .popping ? 1.35 : 1.0)
                    .contentTransition(.symbolEffect(.replace))
            } animation: { phase in
                switch phase {
                case .idle: .spring(response: 0.3, dampingFraction: 0.5, blendDuration: 0)
                case .popping: .spring(response: 0.35, dampingFraction: 0.6, blendDuration: 0)
                }
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: track.isFavorite)
        .frame(width: size + 8, height: size + 8)
    }
}
