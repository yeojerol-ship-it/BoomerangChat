import SwiftUI

// MARK: - Design tokens
private let brandBlue   = Color(red: 66/255,  green: 87/255,  blue: 255/255)  // #4257FF
private let ringBg      = Color(red: 117/255, green: 181/255, blue: 255/255).opacity(0.18)
private let ringBorder  = Color(red: 117/255, green: 181/255, blue: 255/255).opacity(0.08)
private let neutralBtn  = Color.black.opacity(0.05)

// Figma frame constants (844pt tall logical frame)
private let frameH: CGFloat   = 844
private let circleY: CGFloat  = 173   // top of 352×352 camera circle
private let circleD: CGFloat  = 352
/// Recording progress ring (logical pt, scaled with layout).
private let recordingProgressRingD: CGFloat = 340
private let recordingProgressLineWidth: CGFloat = 6
private let recordingProgressColor = Color.white.opacity(0.4)  // #FFFFFF @ 40%
private let timerY: CGFloat   = circleY + circleD + 16   // 541
private let buttonY: CGFloat  = 684   // top of stop / action row

/// Starting center Y for the camera orb before it animates into layout (logical pt).
private let recordingCameraStartY: CGFloat = 670

/// Full-screen recording: one surface with blur + camera transition from chat gesture.
struct BoomerangOverlayView: View {
    @StateObject private var camera = CameraManager()
    @Binding var isPresented: Bool
    var onSend: (URL) -> Void
    /// Target frame (in screen coordinates) for the send animation destination.
    var sendTargetFrame: CGRect = .zero

    @State private var phase: Phase = .recording
    @State private var blurOpacity: Double = 0
    @State private var cameraLift: CGFloat = 0
    @State private var cameraPop: CGFloat = 0
    @State private var chromeOpacity: CGFloat = 0
    @State private var buttonPop: CGFloat = 0
    /// 0→1 drives the send fly-out animation (position + scale). Unused during dismiss (instant fade).
    @State private var sendProgress: CGFloat = 0
    /// Whole overlay fades out on dismiss (no camera scale / Y exit).
    @State private var overlayContentOpacity: Double = 1

    enum Phase { case recording, postRecording }

    private let dismissFadeDuration: Double = 0.1

    var body: some View {
        GeometryReader { geo in
            let safeTop = geo.safeAreaInsets.top
            let layoutScale = geo.size.height / frameH
            let finalCenterY = (circleY + circleD / 2) * layoutScale + safeTop * (1 - layoutScale)
            let currentCenterY = recordingCameraStartY + (finalCenterY - recordingCameraStartY) * cameraLift
            let fullDiameter = circleD * layoutScale

            // Send animation: interpolate from recording orb to chat bubble target
            let targetCenterX = sendTargetFrame.midX
            let targetCenterY = sendTargetFrame.midY
            let targetScale = sendTargetFrame.isEmpty ? 0.001 : sendTargetFrame.width / fullDiameter
            let orbCenterX = geo.size.width / 2 + (targetCenterX - geo.size.width / 2) * sendProgress
            let orbCenterY = currentCenterY + (targetCenterY - currentCenterY) * sendProgress
            let orbScale = 1 + (targetScale - 1) * sendProgress

            ZStack {
                // ── Dismiss layer: covers entire screen ──────────────
                Color.clear
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { dismissWithoutSending() }

                // ── Blur background (non-interactive) ────────────────
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .opacity(blurOpacity)
                    .allowsHitTesting(false)

                // ── Camera orb ───────────────────────────────────────
                ZStack {
                    Circle().fill(ringBg)
                        .overlay(Circle().stroke(ringBorder, lineWidth: 1))

                    CameraPreviewView(previewLayer: camera.previewLayer)
                        .clipShape(Circle())

                    Circle().stroke(Color.white.opacity(0.15), lineWidth: 5)

                    if phase == .recording, camera.isRecording {
                        let ringD = recordingProgressRingD * layoutScale
                        let lineW = recordingProgressLineWidth * layoutScale
                        let progress = min(
                            1,
                            camera.recordingTime / CameraManager.maxRecordingDuration
                        )
                        Circle()
                            .trim(from: 0, to: progress)
                            .stroke(
                                recordingProgressColor,
                                style: StrokeStyle(lineWidth: lineW, lineCap: .round)
                            )
                            .frame(width: ringD, height: ringD)
                            .rotationEffect(.degrees(-90))
                    }
                }
                .frame(width: fullDiameter, height: fullDiameter)
                .clipShape(Circle())
                .scaleEffect(max(0.001, cameraPop * (sendProgress > 0 ? orbScale : 1)), anchor: .center)
                .contentShape(Circle())
                .onTapGesture { /* absorb taps on circle */ }
                .position(
                    x: sendProgress > 0 ? orbCenterX : geo.size.width / 2,
                    y: sendProgress > 0 ? orbCenterY : currentCenterY
                )

                // ── Timer ────────────────────────────────────────────
                HStack(spacing: 6) {
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                    Text(timeString(camera.recordingTime))
                        .font(.system(size: 13, weight: .semibold))
                }
                .position(
                    x: geo.size.width / 2,
                    y: timerY * layoutScale + safeTop * (1 - layoutScale)
                )
                .opacity(chromeOpacity)
                .allowsHitTesting(false)

                // ── Action buttons (fixed size hit area) ─────────────
                actionButtons(scale: layoutScale, buttonPop: buttonPop)
                    .fixedSize()
                    .opacity(chromeOpacity)
                    .position(
                        x: geo.size.width / 2,
                        y: (buttonY + 45) * layoutScale + safeTop * (1 - layoutScale)
                    )
            }
            .opacity(overlayContentOpacity)
            .allowsHitTesting(overlayContentOpacity > 0.5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { runEnterTransition() }
    }

    private func runEnterTransition() {
        blurOpacity = 0
        cameraLift = 0
        cameraPop = 0
        chromeOpacity = 0
        buttonPop = 0
        sendProgress = 0
        overlayContentOpacity = 1

        withAnimation(.easeOut(duration: 0.25)) {
            blurOpacity = 1
        }
        // Camera orb lifts into position with a bouncy spring
        withAnimation(.spring(response: 0.5, dampingFraction: 0.55, blendDuration: 0)) {
            cameraLift = 1
        }
        // Scale pop follows slightly behind the lift for a staggered feel
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.5, blendDuration: 0)) {
                cameraPop = 1
            }
        }
        // Chrome fades in as the orb settles
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeOut(duration: 0.2)) {
                chromeOpacity = 1
            }
        }
        // Stop button bounces in after camera orb
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                buttonPop = 1
            }
        }
        Task { @MainActor in
            var spins = 0
            while camera.previewLayer == nil && spins < 80 {
                try? await Task.sleep(for: .milliseconds(50))
                spins += 1
            }
            try? await Task.sleep(for: .milliseconds(140))
            camera.startRecording()
        }
    }

    // MARK: - Action buttons
    @ViewBuilder
    private func actionButtons(scale: CGFloat, buttonPop: CGFloat) -> some View {
        switch phase {
        case .recording:
            Button { stopAndReview() } label: {
                ZStack {
                    Circle().fill(brandBlue).frame(width: 90 * scale, height: 90 * scale)
                    RoundedRectangle(cornerRadius: 4 * scale)
                        .fill(Color.white)
                        .frame(width: 32 * scale, height: 32 * scale)
                }
            }
            .scaleEffect(buttonPop, anchor: .center)

        case .postRecording:
            HStack(spacing: 40 * scale) {
                postRecordingSquareButton(asset: "recording_retake", scale: scale, action: retake)
                    .scaleEffect(buttonPop, anchor: .center)

                Button { sendToChat() } label: {
                    ZStack {
                        Circle().fill(brandBlue).frame(width: 90 * scale, height: 90 * scale)
                        Image("recording_send")
                            .renderingMode(.template)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: 32 * scale, height: 32 * scale)
                            .foregroundColor(.white)
                    }
                }
                .scaleEffect(buttonPop, anchor: .center)

                postRecordingSquareButton(asset: "recording_download", scale: scale, action: downloadVideo)
                    .scaleEffect(buttonPop, anchor: .center)
            }
        }
    }

    /// Post-review retake / download — uses design PNGs (original colors).
    private func postRecordingSquareButton(asset: String, scale: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 20 * scale)
                    .fill(neutralBtn)
                    .frame(width: 68 * scale, height: 68 * scale)
                Image(asset)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 24 * scale, height: 24 * scale)
            }
        }
    }

    private func timeString(_ t: TimeInterval) -> String {
        let s = Int(t); return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// Fades the full overlay in `dismissFadeDuration`, then stops capture and dismisses (no orb motion).
    private func dismissWithFade() {
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) {
            sendProgress = 0
        }
        withAnimation(.linear(duration: dismissFadeDuration)) {
            overlayContentOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + dismissFadeDuration) {
            camera.stopSession()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isPresented = false
                overlayContentOpacity = 1
            }
        }
    }

    private func stopAndReview() {
        camera.stopRecording()
        buttonPop = 0
        phase = .postRecording
        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
            buttonPop = 1
        }
    }

    private func retake() {
        camera.recordedVideoURL = nil
        camera.recordingTime    = 0
        phase = .recording
        buttonPop = 0
        withAnimation(.easeOut(duration: 0.2)) { chromeOpacity = 1 }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
            buttonPop = 1
        }
        camera.startRecording()
    }

    private func sendToChat() {
        guard let url = camera.recordedVideoURL else { return }
        onSend(url)
        dismissWithFade()
    }

    private func downloadVideo() {
        if let url = camera.recordedVideoURL { camera.saveToPhotoLibrary(url: url) }
    }

    private func dismissWithoutSending() {
        camera.stopRecording()
        dismissWithFade()
    }
}
