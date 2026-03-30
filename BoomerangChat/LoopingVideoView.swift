import SwiftUI
import AVKit
import AVFoundation

/// Looping, muted video that fills its container (uses `AVPlayerLooper` for stable loops).
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

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            clipsToBounds = true
        }

        required init?(coder: NSCoder) { fatalError() }

        /// Compare filesystem paths so SwiftUI updates do not reload the same file every frame.
        func loadVideoIfNeeded(url: URL) {
            let path = url.path
            guard !path.isEmpty else { return }

            if path == loadedPath {
                ensurePlaying()
                return
            }

            guard FileManager.default.fileExists(atPath: path) else {
                return
            }

            cleanup()

            let template = AVPlayerItem(url: url)
            let player = AVQueuePlayer()
            player.isMuted = true

            let playerLooper = AVPlayerLooper(player: player, templateItem: template)

            let layer = AVPlayerLayer(player: player)
            layer.videoGravity = .resizeAspectFill
            layer.frame = bounds
            self.layer.addSublayer(layer)

            playerLayer = layer
            queuePlayer = player
            looper = playerLooper
            loadedPath = path

            statusObservation = template.observe(\.status, options: [.new]) { [weak self, weak player] item, _ in
                guard item.status == .readyToPlay else { return }
                player?.play()
                self?.clearStatusObservation()
            }

            if template.status == .readyToPlay {
                player.play()
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
