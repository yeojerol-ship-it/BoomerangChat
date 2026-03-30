import SwiftUI

private struct BubbleFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

struct ChatView: View {
    @State private var sentBoomerangs: [URL] = []
    @State private var showBoomerang = false
    /// Target frame for the send animation (screen coordinates).
    @State private var sendTargetFrame: CGRect = .zero
    /// Index of the bubble currently being animated in (hidden until fly-in completes).
    @State private var flyingBubbleIndex: Int? = nil


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
    private let inputBarHeight: CGFloat = 132.5
    /// Space between the bottom of the chat-mid thread region and the input / action bar.
    private let threadToInputGap: CGFloat = 24
    /// Inset of messages from the left/right edges of the chat-mid thread list.
    private let threadMessageInset: CGFloat = 16
    private let cameraEntranceBottomPadding: CGFloat = 50
    private let cameraProgressRingSize: CGFloat = 72
    private let cameraProgressLineWidth: CGFloat = 4
    private let cameraPullIconSize: CGFloat = 24
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

    /// Bubble size for sent boomerangs.
    private let bubbleSize: CGFloat = 200

    var body: some View {
        GeometryReader { geo in
            let threadAreaHeight = max(
                0,
                geo.size.height - chatTopHeight - inputBarHeight - threadToInputGap
            )
            ZStack {
                ZStack(alignment: .bottom) {
                    // Thread column sits below the header slot; chat_top is overlaid on top so
                    // pull-up offset never draws chat_mid over the header.
                    ZStack(alignment: .top) {
                        VStack(spacing: 0) {
                            Color.clear
                                .frame(width: geo.size.width, height: chatTopHeight)

                            // Thread list: chat_mid (existing messages) + sent boomerangs appended below.
                            ScrollViewReader { proxy in
                                ScrollView(.vertical, showsIndicators: false) {
                                    VStack(spacing: 0) {
                                        // Existing chat messages (static image)
                                        Image("chat_mid")
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: geo.size.width)

                                        // Sent boomerang videos appended as new messages
                                        if !sentBoomerangs.isEmpty {
                                            VStack(alignment: .trailing, spacing: 8) {
                                                ForEach(sentBoomerangs.indices, id: \.self) { i in
                                                    SentBoomerangBubble(url: sentBoomerangs[i])
                                                        .id(i)
                                                        // Hide bubble while the orb is flying to its position
                                                        .opacity(flyingBubbleIndex == i ? 0 : 1)
                                                        // Report the flying bubble's actual screen position
                                                        .overlay {
                                                            if flyingBubbleIndex == i {
                                                                GeometryReader { bubbleGeo in
                                                                    Color.clear
                                                                        .preference(
                                                                            key: BubbleFrameKey.self,
                                                                            value: bubbleGeo.frame(in: .global)
                                                                        )
                                                                }
                                                            }
                                                        }
                                                }
                                            }
                                            .frame(maxWidth: .infinity, alignment: .trailing)
                                            .padding(.horizontal, threadMessageInset)
                                            .padding(.top, threadMessageInset)
                                            .padding(.bottom, threadMessageInset)
                                        }
                                    }
                                }
                                .onChange(of: sentBoomerangs.count) { _, newCount in
                                    guard newCount > 0 else { return }
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                                        withAnimation(.easeOut(duration: 0.15)) {
                                            proxy.scrollTo(newCount - 1, anchor: .bottom)
                                        }
                                    }
                                }
                            }
                            .frame(width: geo.size.width, height: threadAreaHeight)
                            .clipped()
                            .onPreferenceChange(BubbleFrameKey.self) { frame in
                                if frame != .zero { sendTargetFrame = frame }
                            }
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
                        onSend: { url in beginSendAnimation(url: url) },
                        sendTargetFrame: sendTargetFrame
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

    /// Called by the overlay when user taps send: add bubble hidden, then reveal after overlay fade-out.
    private func beginSendAnimation(url: URL) {
        let newIndex = sentBoomerangs.count
        flyingBubbleIndex = newIndex
        let playbackURL = persistSentVideo(from: url) ?? url
        sentBoomerangs.append(playbackURL)
        // Match BoomerangOverlayView dismiss: 100ms fade + brief stopSession delay.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            flyingBubbleIndex = nil
        }
    }

    /// Copy out of `tmp` so the file survives overlay teardown and system temp cleanup.
    private func persistSentVideo(from tempURL: URL) -> URL? {
        let fm = FileManager.default
        guard let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = support.appendingPathComponent("SentBoomerangs", isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest)
            }
            try fm.copyItem(at: tempURL, to: dest)
            return dest
        } catch {
            print("[ChatView] persistSentVideo failed: \(error.localizedDescription)")
            return nil
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
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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
            // Behind the ring + button so copy and emojis never sit on top of the pull orb.
            ZStack {
                Text("Say cheese!")
                    .font(.system(size: 12))
                    .foregroundColor(Color.black.opacity(0.48))
                    .offset(y: 56)
                    .opacity(Double(pullOpacity))

                emojiView("🤩", size: 20, rotation: 13.78,
                          dx: 50, dy: -30, progress: progress)
                emojiView("😍", size: 24, rotation: -18.27,
                          dx: -40, dy: -44, progress: progress)
                emojiView("🤪", size: 16, rotation: -13.32,
                          dx: -50, dy: 30, progress: progress)
            }
            .allowsHitTesting(false)

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
                    .fill(brandBlue.opacity(0.18))
                    .frame(width: 60, height: 60)
                    .overlay {
                        Image("camera_pull")
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: cameraPullIconSize, height: cameraPullIconSize)
                    }
            }
            .scaleEffect(pullScale)
            .opacity(pullOpacity)
            .allowsHitTesting(false)
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
