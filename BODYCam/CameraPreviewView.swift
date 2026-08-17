import SwiftUI
import AVFoundation

// Maps UIInterfaceOrientation to the AVCaptureVideoOrientation needed so
// photos/video come out right-side-up instead of sideways when captured in
// landscape. Deliberately NOT based on UIDevice.current.orientation — that's
// the raw accelerometer reading, and it's unreliable whenever the phone isn't
// held perfectly upright (routine while actually filming/shooting): it
// frequently reports .faceUp/.faceDown/.unknown instead of the real landscape
// state, which silently skipped the orientation fix and left those captures
// sideways. Interface orientation reflects how the window is actually
// rotated and doesn't have that failure mode. Unlike device orientation,
// landscapeLeft/Right map DIRECTLY here (no swap) — device orientation
// describes which way the phone is physically tilted, interface orientation
// already describes the rotation needed for correct viewing, same as
// AVCaptureVideoOrientation itself.
extension AVCaptureVideoOrientation {
    init?(interfaceOrientation: UIInterfaceOrientation) {
        switch interfaceOrientation {
        case .portrait:           self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft:      self = .landscapeLeft
        case .landscapeRight:     self = .landscapeRight
        default:                  return nil
        }
    }
}

/// Current capture orientation, read from the window's actual interface
/// orientation rather than the accelerometer. Falls back to portrait if no
/// window scene is available yet (e.g. very early during launch).
func currentCaptureOrientation() -> AVCaptureVideoOrientation {
    let interfaceOrientation = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.interfaceOrientation
    return AVCaptureVideoOrientation(interfaceOrientation: interfaceOrientation ?? .portrait) ?? .portrait
}

/// Applies tap-to-focus at a normalized device point (0...1, from
/// `captureDevicePointConverted`).
///
/// Sets exposure as well as focus, matching the native Camera app — focusing
/// without re-metering looks broken in tricky lighting. Every capability is
/// probed first: front cameras commonly support neither point of interest, in
/// which case this silently does nothing rather than throwing.
///
/// The device is taken from the session's own inputs rather than
/// `AVCaptureDevice.default(for: .video)`, so it still targets the right camera
/// after the user flips to the front one.
func applyTapToFocus(session: AVCaptureSession?,
                     devicePoint: CGPoint,
                     on queue: DispatchQueue) {
    guard let session else { return }
    queue.async {
        guard let device = session.inputs
            .compactMap({ $0 as? AVCaptureDeviceInput })
            .first(where: { $0.device.hasMediaType(.video) })?.device
        else { return }

        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = devicePoint
            }
            if device.isFocusModeSupported(.autoFocus) {
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = devicePoint
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
        } catch {
            print("Tap to focus failed: \(error)")
        }
    }
}

/// Restores continuous autofocus/exposure across the whole frame. Called after
/// flipping cameras so the new camera doesn't inherit the old one's focus point.
func resetFocusToContinuous(session: AVCaptureSession?, on queue: DispatchQueue) {
    guard let session else { return }
    queue.async {
        guard let device = session.inputs
            .compactMap({ $0 as? AVCaptureDeviceInput })
            .first(where: { $0.device.hasMediaType(.video) })?.device
        else { return }

        do {
            try device.lockForConfiguration()
            let centre = CGPoint(x: 0.5, y: 0.5)
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = centre
            }
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = centre
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
        } catch {
            print("Focus reset failed: \(error)")
        }
    }
}

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    /// Receives a normalized device point (0...1) when the user taps to focus.
    var onFocusTap: ((CGPoint) -> Void)? = nil

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.applyCurrentOrientation()
        view.onFocusTap = onFocusTap
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.onFocusTap = onFocusTap
    }

    class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        var onFocusTap: ((CGPoint) -> Void)?
        private weak var focusIndicator: UIView?

        override init(frame: CGRect) {
            super.init(frame: frame)
            NotificationCenter.default.addObserver(
                self, selector: #selector(applyCurrentOrientation),
                name: UIDevice.orientationDidChangeNotification, object: nil)

            // The tap lives here rather than as a SwiftUI .onTapGesture because
            // converting a tap into a sensor coordinate needs the preview layer:
            // videoGravity is .resizeAspectFill, so the visible image is cropped
            // and view coordinates do NOT map linearly onto the sensor.
            addGestureRecognizer(
                UITapGestureRecognizer(target: self, action: #selector(handleFocusTap(_:)))
            )
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        @objc private func handleFocusTap(_ recognizer: UITapGestureRecognizer) {
            guard let onFocusTap else { return }
            let viewPoint = recognizer.location(in: self)
            let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: viewPoint)
            showFocusIndicator(at: viewPoint)
            onFocusTap(devicePoint)
        }

        /// Brief square at the tap point. Without visible feedback a tap that
        /// silently adjusts focus feels like nothing happened at all.
        private func showFocusIndicator(at point: CGPoint) {
            focusIndicator?.removeFromSuperview()

            let box = UIView(frame: CGRect(x: 0, y: 0, width: 72, height: 72))
            box.center = point
            box.layer.borderColor = UIColor.systemYellow.cgColor
            box.layer.borderWidth = 1.5
            box.layer.cornerRadius = 4
            box.isUserInteractionEnabled = false
            box.alpha = 0
            box.transform = CGAffineTransform(scaleX: 1.35, y: 1.35)
            addSubview(box)
            focusIndicator = box

            UIView.animate(withDuration: 0.18, animations: {
                box.alpha = 1
                box.transform = .identity
            }, completion: { _ in
                UIView.animate(withDuration: 0.4, delay: 0.7, options: [], animations: {
                    box.alpha = 0
                }, completion: { _ in
                    box.removeFromSuperview()
                })
            })
        }

        // Keeps the LIVE PREVIEW's orientation matching the device as it
        // rotates. This only affects the on-screen preview — actual capture
        // orientation is set separately, right before each recording/photo,
        // in ContentView/PhotoCameraView. The device-orientation notification
        // is used only as a "something rotated, recheck" trigger — the actual
        // value always comes from currentCaptureOrientation().
        @objc func applyCurrentOrientation() {
            guard let connection = previewLayer.connection else { return }
            connection.videoOrientation = currentCaptureOrientation()
        }
    }
}
