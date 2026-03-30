import SwiftUI
import AVKit
import AVFoundation

/// Looping, muted video that fills its container.
/// Uses a plain AVPlayer with manual seek-to-start on end for reliable looping.
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
        private var player: AVPlayer?
        private var loadedPath: String?
        private var endObserver: NSObjectProtocol?
        private var stallObserver: NSObjectProtocol?
        private var statusObservation: NSKeyValueObservation?
        private var timeControlObservation: NSKeyValueObservation?

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

            guard FileManager.default.fileExists(atPath: path) else { return }

            cleanup()
            let fileURL = url.standardizedFileURL

            let asset = AVURLAsset(url: fileURL, options: [
                AVURLAssetPreferPreciseDurationAndTimingKey: true
            ])
            let item = AVPlayerItem(asset: asset)
            item.preferredForwardBufferDuration = 2.0

            let newPlayer = AVPlayer(playerItem: item)
            newPlayer.isMuted = true
            newPlayer.automaticallyWaitsToMinimizeStalling = false

            let layer = AVPlayerLayer(player: newPlayer)
            layer.videoGravity = .resizeAspectFill
            layer.frame = bounds
            self.layer.addSublayer(layer)

            self.playerLayer = layer
            self.player = newPlayer
            self.loadedPath = path

            // Loop: when playback ends, seek to start and play again
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                guard let self, let player = self.player else { return }
                player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
                    if finished {
                        player.play()
                    }
                }
            }

            // Recovery: if playback stalls, try to resume
            stallObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemPlaybackStalled,
                object: item,
                queue: .main
            ) { [weak self] _ in
                self?.player?.play()
            }

            // Watch timeControlStatus to detect pauses and auto-resume
            timeControlObservation = newPlayer.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if player.timeControlStatus == .paused,
                       let item = player.currentItem,
                       item.status == .readyToPlay {
                        // If paused but ready, resume — handles edge-case stalls
                        player.play()
                    }
                }
            }

            // Start playback once ready
            statusObservation = item.observe(\.status, options: [.new]) { [weak newPlayer] item, _ in
                if item.status == .readyToPlay {
                    newPlayer?.play()
                }
            }

            // In case it's immediately ready
            if item.status == .readyToPlay {
                newPlayer.play()
            }
        }

        func ensurePlaying() {
            guard let player else { return }
            if player.rate == 0, player.currentItem?.status == .readyToPlay {
                player.play()
            }
        }

        func cleanup() {
            if let endObserver {
                NotificationCenter.default.removeObserver(endObserver)
            }
            endObserver = nil
            if let stallObserver {
                NotificationCenter.default.removeObserver(stallObserver)
            }
            stallObserver = nil
            statusObservation?.invalidate()
            statusObservation = nil
            timeControlObservation?.invalidate()
            timeControlObservation = nil
            player?.pause()
            player = nil
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
            if let endObserver {
                NotificationCenter.default.removeObserver(endObserver)
            }
            if let stallObserver {
                NotificationCenter.default.removeObserver(stallObserver)
            }
            statusObservation?.invalidate()
            timeControlObservation?.invalidate()
            player?.pause()
        }
    }
}
