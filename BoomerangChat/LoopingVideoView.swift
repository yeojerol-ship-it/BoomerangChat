import SwiftUI
import AVKit
import AVFoundation

/// Looping, muted video player that fills its container.
struct LoopingVideoView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> LoopingPlayerUIView {
        LoopingPlayerUIView(url: url)
    }

    func updateUIView(_ uiView: LoopingPlayerUIView, context: Context) {}

    class LoopingPlayerUIView: UIView {
        private var playerLayer: AVPlayerLayer?
        private var loopToken: NSObjectProtocol?
        private let player: AVQueuePlayer
        private var looper: AVPlayerLooper?

        init(url: URL) {
            let item = AVPlayerItem(url: url)
            player = AVQueuePlayer(playerItem: item)
            player.isMuted = true
            super.init(frame: .zero)
            looper = AVPlayerLooper(player: player, templateItem: item)
            let layer = AVPlayerLayer(player: player)
            layer.videoGravity = .resizeAspectFill
            self.layer.addSublayer(layer)
            playerLayer = layer
            player.play()
        }

        required init?(coder: NSCoder) { fatalError() }

        override func layoutSubviews() {
            super.layoutSubviews()
            playerLayer?.frame = bounds
        }
    }
}
