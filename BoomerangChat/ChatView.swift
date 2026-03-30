import SwiftUI

struct ChatView: View {
    @State private var sentBoomerangs: [URL] = []
    @State private var showBoomerang = false

    @State private var dragOffset: CGFloat = 0
    /// True after 100ms long-press succeeds; drag + fades only then.
    @State private var pullUnlocked = false
    /// Light haptic once per pull when upward drag starts (avoids buzzing).
    @State private var didFireScrollUpHaptic = false
    /// Blocks duplicate present calls while `showBoomerang` flips on the next run loop.
    @State private var isOpeningRecording = false

    private let longPressDuration: Double = 0.1
    private let triggerThreshold: CGFloat = 100
    private let chatTopHeight: CGFloat = 104
    private let threadHeight: CGFloat = 549
    private let inputBarHeight: CGFloat = 132.5
    private let cameraEntranceBottomPadding: CGFloat = 50
    private let cameraProgressRingSize: CGFloat = 74
    private let cameraProgressLineWidth: CGFloat = 2
    private let brandBlue = Color(red: 66/255, green: 87/255, blue: 255/255)  // #4257FF
    private let snapBackSpring = Animation.spring(response: 0.38, dampingFraction: 0.82)

    /// Hidden once pull moves a few points (avoids opacity flicker at 0).
    private var inputBarFadeOpacity: Double {
        guard pullUnlocked else { return 1 }
        return dragOffset > 3 ? 0 : 1
    }

    /// Blur over chat once pull is unlocked; strengthens with drag.
    private var chatBlurOpacity: Double {
        guard pullUnlocked else { return 0 }
        return min(Double(dragOffset / triggerThreshold), 1) * 0.88
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ZStack(alignment: .bottom) {
                    // Thread column sits below the header slot; chat_top is overlaid on top so
                    // pull-up offset never draws chat_mid over the header.
                    ZStack(alignment: .top) {
                        VStack(spacing: 0) {
                            Color.clear
                                .frame(width: geo.size.width, height: chatTopHeight)

                            ZStack(alignment: .bottomTrailing) {
                                Image("chat_mid")
                                    .resizable()
                                    .frame(width: geo.size.width, height: threadHeight)

                                if !sentBoomerangs.isEmpty && !showBoomerang {
                                    VStack(alignment: .trailing, spacing: 8) {
                                        ForEach(sentBoomerangs.indices, id: \.self) { i in
                                            SentBoomerangBubble(url: sentBoomerangs[i])
                                        }
                                    }
                                    .padding(.trailing, 16)
                                    .padding(.bottom, 16)
                                }
                            }
                            .frame(width: geo.size.width, height: threadHeight, alignment: .top)
                            .contentShape(Rectangle())
                            .gesture(threadPullGesture, isEnabled: !showBoomerang)
                            .offset(y: -dragOffset)

                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .ignoresSafeArea()

                        Image("chat_top")
                            .resizable()
                            .frame(width: geo.size.width, height: chatTopHeight)
                            .frame(maxWidth: .infinity, alignment: .top)
                            .allowsHitTesting(false)
                            .ignoresSafeArea()
                    }

                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea()
                        .opacity(chatBlurOpacity)
                        .allowsHitTesting(false)

                    cameraEntrance()
                        .opacity(
                            showBoomerang
                                ? 0
                                : (pullUnlocked && dragOffset > 0 ? 1 : 0)
                        )

                    VStack {
                        Spacer(minLength: 0)
                        Image("chat_bottom")
                            .resizable()
                            .frame(width: geo.size.width, height: inputBarHeight)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .opacity(inputBarFadeOpacity)
                    .allowsHitTesting(inputBarFadeOpacity > 0.05)
                    .ignoresSafeArea()
                }

                if showBoomerang {
                    BoomerangOverlayView(
                        isPresented: $showBoomerang,
                        onSend: { url in sentBoomerangs.append(url) }
                    )
                    .frame(width: geo.size.width, height: geo.size.height)
                    .zIndex(2000)
                    .transition(.identity)
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Long-press (100ms) then pull-up
    private var threadPullGesture: some Gesture {
        LongPressGesture(minimumDuration: longPressDuration, maximumDistance: 80)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                switch value {
                case .second(true, let drag):
                    if !pullUnlocked { pullUnlocked = true }
                    guard let drag else { return }
                    let raw = max(0, -drag.translation.height)
                    let up = (raw * 4).rounded() / 4
                    if !didFireScrollUpHaptic, up > 6 {
                        didFireScrollUpHaptic = true
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                    if up >= triggerThreshold {
                        presentRecordingOverlay()
                        return
                    }
                    guard !showBoomerang else { return }
                    var next: CGFloat
                    if up < triggerThreshold {
                        next = up
                    } else {
                        let excess = up - triggerThreshold
                        next = triggerThreshold + excess * 0.3
                    }
                    var tx = Transaction()
                    tx.disablesAnimations = true
                    withTransaction(tx) { dragOffset = next }
                default:
                    break
                }
            }
            .onEnded { value in
                if showBoomerang { return }
                switch value {
                case .second(true, let drag):
                    guard let drag else {
                        resetPullState(animated: true)
                        return
                    }
                    let up = max(0, -drag.translation.height)
                    let passed = up >= triggerThreshold || dragOffset >= triggerThreshold
                    if passed {
                        presentRecordingOverlay()
                    } else {
                        resetPullState(animated: true)
                    }
                default:
                    resetPullState(animated: true)
                }
            }
    }

    private func resetPullState(animated: Bool) {
        pullUnlocked = false
        didFireScrollUpHaptic = false
        isOpeningRecording = false
        if animated {
            withAnimation(snapBackSpring) { dragOffset = 0 }
        } else {
            var tx = Transaction()
            tx.disablesAnimations = true
            withTransaction(tx) { dragOffset = 0 }
        }
    }

    private func presentRecordingOverlay() {
        guard !showBoomerang, !isOpeningRecording else { return }
        isOpeningRecording = true
        pullUnlocked = false
        didFireScrollUpHaptic = false
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) { dragOffset = 0 }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        DispatchQueue.main.async {
            showBoomerang = true
            isOpeningRecording = false
        }
    }

    // MARK: - Camera orb (pull preview)
    private func cameraEntrance() -> some View {
        let progress = min(dragOffset / triggerThreshold, 1.0)
        let pullScale = min(progress * 1.2, 1)
        let pullOpacity = min(progress * 1.5, 1)

        return ZStack {
            ZStack {
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        brandBlue,
                        style: StrokeStyle(lineWidth: cameraProgressLineWidth, lineCap: .round)
                    )
                    .frame(width: cameraProgressRingSize, height: cameraProgressRingSize)
                    .rotationEffect(.degrees(-90))

                Circle()
                    .fill(brandBlue)
                    .frame(width: 60, height: 60)
                    .overlay {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.white)
                    }
            }
            .scaleEffect(pullScale)
            .opacity(pullOpacity)

            emojiView("🤩", size: 20, rotation: 13.78,
                      dx: 50, dy: -30, progress: progress)
            emojiView("😍", size: 24, rotation: -18.27,
                      dx: -40, dy: -44, progress: progress)
            emojiView("🤪", size: 16, rotation: -13.32,
                      dx: -50, dy: 30, progress: progress)
        }
        .padding(.bottom, cameraEntranceBottomPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .allowsHitTesting(false)
    }

    private func emojiView(
        _ emoji: String, size: CGFloat, rotation: Double,
        dx: CGFloat, dy: CGFloat, progress: CGFloat
    ) -> some View {
        Text(emoji)
            .font(.system(size: size))
            .rotationEffect(.degrees(rotation))
            .offset(x: dx * progress, y: dy * progress)
            .scaleEffect(progress)
            .opacity(Double(progress))
    }
}

// MARK: - Sent boomerang bubble (200×200, right-aligned, 16pt from thread)
struct SentBoomerangBubble: View {
    let url: URL

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(red: 117/255, green: 181/255, blue: 255/255).opacity(0.18))
                .overlay(Circle().stroke(
                    Color(red: 117/255, green: 181/255, blue: 255/255).opacity(0.08),
                    lineWidth: 1
                ))

            LoopingVideoView(url: url)
                .clipShape(Circle())

            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 5)
        }
        .frame(width: 200, height: 200)
    }
}
