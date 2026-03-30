import AVFoundation
import Photos
import SwiftUI

/// Camera capture: all `AVCaptureSession` work runs on `sessionQueue` to satisfy AVFoundation threading rules.
@MainActor
class CameraManager: NSObject, ObservableObject {
    /// Clip length cap (seconds); overlay progress ring uses the same value.
    static let maxRecordingDuration: TimeInterval = 15

    @Published var isRecording = false
    @Published var recordingTime: TimeInterval = 0
    @Published var recordedVideoURL: URL?
    @Published var previewLayer: AVCaptureVideoPreviewLayer?

    private let session = AVCaptureSession()
    private var movieOutput = AVCaptureMovieFileOutput()
    private var timer: Timer?
    private let sessionQueue = DispatchQueue(label: "com.boomerang.camera.session")

    override init() {
        super.init()
        setupSession()
    }

    deinit {
        // Ensure hardware is released if the overlay is torn down without `stopSession()`.
        sessionQueue.sync {
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    private func setupSession() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            sessionQueue.async { [self] in configureAndStartSession() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [self] granted in
                guard granted else { return }
                sessionQueue.async { [self] in configureAndStartSession() }
            }
        default:
            break
        }
    }

    /// Must run on `sessionQueue` only.
    private func configureAndStartSession() {
        session.beginConfiguration()
        // Lighter than `.high` — less encoder/GPU load and smaller files for smooth chat playback.
        if session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
        } else {
            session.sessionPreset = .high
        }

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
            let input = try? AVCaptureDeviceInput(device: device)
        else {
            session.commitConfiguration()
            return
        }

        if session.canAddInput(input) { session.addInput(input) }

        if let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
           session.canAddInput(audioInput) {
            session.addInput(audioInput)
        }

        if session.canAddOutput(movieOutput) { session.addOutput(movieOutput) }

        movieOutput.connections.first?.isVideoMirrored = true

        session.commitConfiguration()

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.connection?.automaticallyAdjustsVideoMirroring = false
        layer.connection?.isVideoMirrored = true

        session.startRunning()

        DispatchQueue.main.async { [self] in
            self.previewLayer = layer
        }
    }

    func startRecording() {
        guard !isRecording else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mov")

        sessionQueue.async { [self] in
            guard self.session.isRunning,
                  !self.movieOutput.connections.isEmpty,
                  !self.movieOutput.isRecording
            else { return }

            self.movieOutput.startRecording(to: url, recordingDelegate: self)

            DispatchQueue.main.async { [self] in
                self.isRecording = true
                self.recordingTime = 0
                self.timer?.invalidate()
                let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                    guard let self else { return }
                    Task { @MainActor in
                        self.recordingTime += 0.1
                        if self.recordingTime >= Self.maxRecordingDuration {
                            self.stopRecording()
                        }
                    }
                }
                RunLoop.main.add(t, forMode: .common)
                self.timer = t
            }
        }
    }

    func stopRecording() {
        timer?.invalidate()
        timer = nil
        guard isRecording else { return }
        isRecording = false
        sessionQueue.async { [self] in
            if self.movieOutput.isRecording {
                self.movieOutput.stopRecording()
            }
        }
    }

    /// Detach preview first, then stop the session — avoids FigCaptureSourceRemote asserts when the
    /// preview layer is still wired to a running session.
    func stopSession() {
        previewLayer = nil
        sessionQueue.async { [self] in
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    func saveToPhotoLibrary(url: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
        }
    }
}

extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        if let error {
            print("[CameraManager] Recording error: \(error.localizedDescription)")
        }
        let exists = FileManager.default.fileExists(atPath: outputFileURL.path)
        let size = (try? FileManager.default.attributesOfItem(atPath: outputFileURL.path)[.size] as? Int) ?? 0
        print("[CameraManager] Video saved: \(outputFileURL.lastPathComponent), exists=\(exists), size=\(size)")
        Task { @MainActor in
            self.recordedVideoURL = outputFileURL
        }
    }
}
