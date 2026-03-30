import AVFoundation
import Photos
import SwiftUI

@MainActor
class CameraManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var recordingTime: TimeInterval = 0
    @Published var recordedVideoURL: URL?
    @Published var previewLayer: AVCaptureVideoPreviewLayer?

    private let session = AVCaptureSession()
    private var movieOutput = AVCaptureMovieFileOutput()
    private var timer: Timer?
    private let maxDuration: TimeInterval = 15

    override init() {
        super.init()
        Task { await setupSession() }
    }

    private func setupSession() async {
        guard await AVCaptureDevice.requestAccess(for: .video) else { return }

        session.beginConfiguration()
        session.sessionPreset = .high

        // Front camera
        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
            let input = try? AVCaptureDeviceInput(device: device)
        else { session.commitConfiguration(); return }

        if session.canAddInput(input) { session.addInput(input) }

        // Audio
        if let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }

        if session.canAddOutput(movieOutput) { session.addOutput(movieOutput) }

        // Mirror front camera
        movieOutput.connections.first?.isVideoMirrored = true

        session.commitConfiguration()

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.connection?.automaticallyAdjustsVideoMirroring = false
        layer.connection?.isVideoMirrored = true
        previewLayer = layer

        session.startRunning()
    }

    func startRecording() {
        guard !isRecording else { return }
        // No camera available (e.g. Simulator) — skip recording
        guard session.isRunning, !movieOutput.connections.isEmpty else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")
        movieOutput.startRecording(to: url, recordingDelegate: self)
        isRecording = true
        recordingTime = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.recordingTime += 0.1
                if self.recordingTime >= self.maxDuration {
                    self.stopRecording()
                }
            }
        }
    }

    func stopRecording() {
        timer?.invalidate()
        timer = nil
        guard isRecording else { return }
        if movieOutput.isRecording {
            movieOutput.stopRecording()
        }
        isRecording = false
    }

    func saveToPhotoLibrary(url: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
        }
    }

    func stopSession() {
        session.stopRunning()
    }
}

extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor in
            self.recordedVideoURL = outputFileURL
        }
    }
}
