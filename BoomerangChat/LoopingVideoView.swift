import SwiftUI
import AVKit
import AVFoundation

/// Looping, muted video that fills its container (`AVPlayerLooper` + tuned for local short clips).
struct LoopingVideoView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> LoopingPlayerUIView {
        let view = LoopingPlayerUIView()
        view.loadVideoIfNeeded(url: url)
        return view
    }

    func updateUIView(_ uiView: LoopingPlayerUIView, context: Context) {
        uiView.loadVideoIfNeeded(url: url)
    }

    static func dismantleUIView(_ uiView: LoopingPlayerUIView, coordinator: ()) {
        uiView.cleanup()
    }

    final class LoopingPlayerUIView: UIView {
        private var playerLayer: AVPlayerLayer?
        private var queuePlayer: AVQueuePlayer?
        private var looper: AVPlayerLooper?
        private var loadedPath: String?
        private var statusObservation: NSKeyValueObservation?
        private var loadGeneration: UInt64 = 0

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            clipsToBounds = true
        }

        required init?(coder: NSCoder) { fatalError() }

        func loadVideoIfNeeded(url: URL) {
            let path = url.standardizedFileURL.path
            guard !path.isEmpty else { return }

            if path == loadedPath {
                ensurePlaying()
                return
            }

            guard FileManager.default.fileExists(atPath: path) else {
                return
            }

            cleanup()
            loadGeneration += 1
            let generation = loadGeneration
            let fileURL = url.standardizedFileURL

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let template = AVPlayerItem(url: fileURL)
                template.canUseNetworkResourcesForLiveStreamingWhilePaused = false
                template.preferredForwardBufferDuration = 1.0
                if #available(iOS 15.0, *) {
                    // Bubble is small; decode at modest resolution for smoother playback.
                    template.preferredMaximumResolution = CGSize(width: 720, height: 720)
                }

                let player = AVQueuePlayer()
                player.isMuted = true
                player.automaticallyWaitsToMinimizeStalling = false

                let playerLooper = AVPlayerLooper(player: player, templateItem: template)

                DispatchQueue.main.async { [weak self] in
                    guard let self else {
                        player.pause()
                        return
                    }
                    guard generation == self.loadGeneration else {
                        player.pause()
                        return
                    }

                    let layer = AVPlayerLayer(player: player)
                    layer.videoGravity = .resizeAspectFill
                    layer.frame = self.bounds
                    self.layer.addSublayer(layer)

                    self.playerLayer = layer
                    self.queuePlayer = player
                    self.looper = playerLooper
                    self.loadedPath = path

                    self.statusObservation = template.observe(\.status, options: [.new]) { [weak self, weak player] item, _ in
                        guard item.status == .readyToPlay else { return }
                        player?.play()
                        self?.clearStatusObservation()
                    }

                    if template.status == .readyToPlay {
                        player.play()
                    }
                }
            }
        }

        private func clearStatusObservation() {
            statusObservation?.invalidate()
            statusObservation = nil
        }

        func ensurePlaying() {
            guard let player = queuePlayer else { return }
            player.isMuted = true
            if player.rate == 0 {
                player.play()
            }
        }

        func cleanup() {
            clearStatusObservation()
            looper = nil
            queuePlayer?.pause()
            queuePlayer = nil
            playerLayer?.removeFromSuperlayer()
            playerLayer = nil
            loadedPath = nil
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            playerLayer?.frame = bounds
            if bounds.width > 2, bounds.height > 2 {
                ensurePlaying()
            }
        }

        deinit {
            cleanup()
        }
    }
}
