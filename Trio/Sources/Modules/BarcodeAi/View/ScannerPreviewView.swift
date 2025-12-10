import AVFoundation
import CoreImage
import CoreMedia
import SwiftUI

// MARK: - Barcode Scanner Preview

extension BarcodeScanner {
    struct ScannerPreviewView: UIViewRepresentable {
        @Binding var isRunning: Bool
        var supportedTypes: [AVMetadataObject.ObjectType] = [.ean13, .ean8, .upce, .code128, .code39]
        let onDetected: (String) -> Void
        let onFailure: (String) -> Void
        var onFrameCaptured: ((UIImage) -> Void)?

        func makeCoordinator() -> Coordinator {
            Coordinator(
                isRunning: $isRunning,
                supportedTypes: supportedTypes,
                onDetected: onDetected,
                onFailure: onFailure,
                onFrameCaptured: onFrameCaptured
            )
        }

        func makeUIView(context: Context) -> CameraPreviewView {
            let view = CameraPreviewView()
            view.coordinator = context.coordinator
            context.coordinator.attach(to: view)
            return view
        }

        func updateUIView(_: CameraPreviewView, context: Context) {
            context.coordinator.setRunning(isRunning)
        }

        static func dismantleUIView(_: CameraPreviewView, coordinator: Coordinator) {
            coordinator.cleanup()
        }
    }
}

// MARK: - Coordinator

extension BarcodeScanner.ScannerPreviewView {
    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
        private var isRunning: Binding<Bool>
        private let supportedTypes: [AVMetadataObject.ObjectType]
        private let onDetected: (String) -> Void
        private let onFailure: (String) -> Void
        private let onFrameCaptured: ((UIImage) -> Void)?

        private let session = AVCaptureSession()
        private let metadataOutput = AVCaptureMetadataOutput()
        private let videoOutput = AVCaptureVideoDataOutput()
        private var isConfigured = false
        private let videoQueue = DispatchQueue(label: "video.frame.queue")
        private var lastFrameTime: Date = .distantPast
        private let frameInterval: TimeInterval = 0.5

        private var currentDevice: AVCaptureDevice?
        private weak var previewView: CameraPreviewView?
        private var focusObservation: NSKeyValueObservation?
        private var lastFocusTime: Date = .distantPast

        init(
            isRunning: Binding<Bool>,
            supportedTypes: [AVMetadataObject.ObjectType],
            onDetected: @escaping (String) -> Void,
            onFailure: @escaping (String) -> Void,
            onFrameCaptured: ((UIImage) -> Void)?
        ) {
            self.isRunning = isRunning
            self.supportedTypes = supportedTypes
            self.onDetected = onDetected
            self.onFailure = onFailure
            self.onFrameCaptured = onFrameCaptured
            super.init()
        }

        func cleanup() {
            focusObservation?.invalidate()
            focusObservation = nil
            Foundation.NotificationCenter.default.removeObserver(self)
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self, self.session.isRunning else { return }
                self.session.stopRunning()
            }
        }

        func attach(to view: CameraPreviewView) {
            previewView = view
            configureIfNeeded()
            view.videoPreviewLayer.session = session
            view.videoPreviewLayer.videoGravity = .resizeAspectFill
            setRunning(isRunning.wrappedValue)
        }

        func setRunning(_: Bool) {
            guard isConfigured else { return }
            if !session.isRunning {
                startSession()
            }
        }

        func handleTapToFocus(at point: CGPoint, in view: UIView) {
            guard let device = currentDevice,
                  let previewLayer = (view as? CameraPreviewView)?.videoPreviewLayer
            else { return }

            let focusPoint = previewLayer.captureDevicePointConverted(fromLayerPoint: point)

            do {
                try device.lockForConfiguration()

                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = focusPoint
                }

                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = focusPoint
                }

                if device.isFocusModeSupported(.autoFocus) {
                    device.focusMode = .autoFocus
                }

                if device.isExposureModeSupported(.autoExpose) {
                    device.exposureMode = .autoExpose
                }

                device.unlockForConfiguration()
                lastFocusTime = Date()

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                    self?.switchToContinuousAutoFocus()
                }
            } catch {}
        }

        private func switchToContinuousAutoFocus() {
            guard let device = currentDevice else { return }

            do {
                try device.lockForConfiguration()

                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }

                device.unlockForConfiguration()
            } catch {}
        }

        private func setupFocusMonitoring() {
            guard let device = currentDevice else { return }

            Foundation.NotificationCenter.default.addObserver(
                self,
                selector: #selector(subjectAreaDidChange),
                name: NSNotification.Name.AVCaptureDeviceSubjectAreaDidChange,
                object: device
            )

            focusObservation = device.observe(\.lensPosition, options: [.new]) { [weak self] device, _ in
                guard let self else { return }

                let now = Date()
                if now.timeIntervalSince(self.lastFocusTime) > 3.0 {
                    if !device.isAdjustingFocus, device.lensPosition < 0.1 || device.lensPosition > 0.9 {
                        self.triggerRefocus()
                    }
                }
            }
        }

        @objc private func subjectAreaDidChange(_: Notification) {
            guard let device = currentDevice else { return }

            let now = Date()
            guard now.timeIntervalSince(lastFocusTime) > 1.0 else { return }

            do {
                try device.lockForConfiguration()

                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
                }
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }

                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
                }
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }

                device.unlockForConfiguration()
                lastFocusTime = now
            } catch {}
        }

        private func triggerRefocus() {
            guard let device = currentDevice else { return }

            do {
                try device.lockForConfiguration()

                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
                }

                if device.isFocusModeSupported(.autoFocus) {
                    device.focusMode = .autoFocus
                }

                device.unlockForConfiguration()
                lastFocusTime = Date()

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.switchToContinuousAutoFocus()
                }
            } catch {}
        }

        private func configureIfNeeded() {
            guard !isConfigured else { return }

            session.beginConfiguration()
            session.sessionPreset = .high

            let device = getBestCameraForScanning()

            guard let device else {
                onFailure(String(localized: "Camera is not available on this device."))
                session.commitConfiguration()
                return
            }

            currentDevice = device
            configureFocusSettings(for: device)

            do {
                let input = try AVCaptureDeviceInput(device: device)
                guard session.canAddInput(input) else {
                    onFailure(String(localized: "Unable to use the back camera."))
                    session.commitConfiguration()
                    return
                }
                session.addInput(input)
            } catch {
                onFailure(String(localized: "Failed to configure camera: \(error.localizedDescription)"))
                session.commitConfiguration()
                return
            }

            guard session.canAddOutput(metadataOutput) else {
                onFailure(String(localized: "Unable to read barcodes on this device."))
                session.commitConfiguration()
                return
            }

            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = supportedTypes

            if onFrameCaptured != nil, session.canAddOutput(videoOutput) {
                videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
                videoOutput.alwaysDiscardsLateVideoFrames = true
                session.addOutput(videoOutput)
            }

            session.commitConfiguration()
            isConfigured = true

            setupFocusMonitoring()
        }

        private func getBestCameraForScanning() -> AVCaptureDevice? {
            if #available(iOS 15.4, *) {
                if let multiCamera = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) {
                    return multiCamera
                }
                if let tripleCamera = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back) {
                    return tripleCamera
                }
            }

            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        }

        private func configureFocusSettings(for device: AVCaptureDevice) {
            do {
                try device.lockForConfiguration()

                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }

                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
                }

                if device.isAutoFocusRangeRestrictionSupported {
                    device.autoFocusRangeRestriction = .near
                }

                if device.isSubjectAreaChangeMonitoringEnabled == false {
                    device.isSubjectAreaChangeMonitoringEnabled = true
                }

                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
                }

                if device.isLowLightBoostSupported {
                    device.automaticallyEnablesLowLightBoostWhenAvailable = true
                }

                if #available(iOS 15.4, *) {
                    if device.automaticallyAdjustsFaceDrivenAutoFocusEnabled {
                        device.automaticallyAdjustsFaceDrivenAutoFocusEnabled = false
                    }
                }

                device.unlockForConfiguration()
            } catch {}
        }

        private func startSession() {
            guard !session.isRunning else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                self.session.startRunning()
            }
        }

        func metadataOutput(
            _: AVCaptureMetadataOutput,
            didOutput metadataObjects: [AVMetadataObject],
            from _: AVCaptureConnection
        ) {
            guard isRunning.wrappedValue else { return }
            guard let readableObject = metadataObjects.compactMap({ $0 as? AVMetadataMachineReadableCodeObject }).first,
                  let stringValue = readableObject.stringValue
            else {
                return
            }

            onDetected(stringValue)
        }

        func captureOutput(
            _: AVCaptureOutput,
            didOutput sampleBuffer: CMSampleBuffer,
            from _: AVCaptureConnection
        ) {
            let now = Date()
            guard now.timeIntervalSince(lastFrameTime) >= frameInterval else { return }
            lastFrameTime = now

            guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

            let ciImage = CIImage(cvPixelBuffer: imageBuffer)
            let context = CIContext()
            guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }

            let orientation: UIImage.Orientation = .right
            let fullImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: orientation)

            DispatchQueue.main.async { [weak self] in
                self?.onFrameCaptured?(fullImage)
            }
        }
    }
}

// MARK: - Camera Preview View

final class CameraPreviewView: UIView {
    weak var coordinator: BarcodeScanner.ScannerPreviewView.Coordinator?
    private var focusIndicator: UIView?

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupTapGesture()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupTapGesture()
    }

    private func setupTapGesture() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        addGestureRecognizer(tapGesture)
        isUserInteractionEnabled = true
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        coordinator?.handleTapToFocus(at: point, in: self)
        showFocusIndicator(at: point)
    }

    private func showFocusIndicator(at point: CGPoint) {
        focusIndicator?.removeFromSuperview()

        let indicator = UIView(frame: CGRect(x: 0, y: 0, width: 80, height: 80))
        indicator.center = point
        indicator.layer.borderColor = UIColor.systemYellow.cgColor
        indicator.layer.borderWidth = 2
        indicator.layer.cornerRadius = 10
        indicator.backgroundColor = .clear
        indicator.alpha = 0
        addSubview(indicator)
        focusIndicator = indicator

        UIView.animateKeyframes(withDuration: 1.5, delay: 0, options: []) {
            UIView.addKeyframe(withRelativeStartTime: 0, relativeDuration: 0.1) {
                indicator.alpha = 1
                indicator.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
            }
            UIView.addKeyframe(withRelativeStartTime: 0.1, relativeDuration: 0.2) {
                indicator.transform = .identity
            }
            UIView.addKeyframe(withRelativeStartTime: 0.8, relativeDuration: 0.2) {
                indicator.alpha = 0
            }
        } completion: { _ in
            indicator.removeFromSuperview()
        }
    }
}
