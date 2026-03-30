import SwiftUI
import AVFoundation

/// UIViewRepresentable that hosts the AVCaptureVideoPreviewLayer inside a circle clip.
struct CameraPreviewView: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer?

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.clipsToBounds = true
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        if let layer = previewLayer {
            uiView.setPreviewLayer(layer)
        } else {
            uiView.clearPreviewLayer()
        }
    }

    class PreviewUIView: UIView {
        private var currentLayer: AVCaptureVideoPreviewLayer?

        func setPreviewLayer(_ layer: AVCaptureVideoPreviewLayer) {
            guard layer !== currentLayer else {
                layer.frame = bounds
                return
            }
            currentLayer?.removeFromSuperlayer()
            currentLayer = layer
            layer.frame = bounds
            layer.videoGravity = .resizeAspectFill
            self.layer.addSublayer(layer)
        }

        func clearPreviewLayer() {
            currentLayer?.removeFromSuperlayer()
            currentLayer = nil
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            currentLayer?.frame = bounds
        }
    }
}
