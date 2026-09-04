import SwiftUI
import AVFoundation

/// One serial queue for ALL AVCaptureSession work across BOTH the Video and
/// Photo tabs — they used to each have their own. That looked correct in
/// isolation (Apple does require session work to run on a dedicated serial
/// queue, and each tab had one), but a tab switch fires the outgoing tab's
/// onDisappear and the incoming tab's onAppear back to back on the main
/// thread, and each side only ENQUEUED its own release/claim of the shared
/// physical AVCaptureDevice onto its own queue — nothing tied those two
/// queues' orderings together. Two independently-correct serial queues give
/// you no guarantee about their order relative to EACH OTHER, only within
/// themselves.
///
/// Confirmed as a real bug, not just a theoretical one: recording, stopping,
/// and switching Video → Photo → Video in quick succession froze the camera
/// on a real iPhone SE, recovering only once backgrounding the app forced
/// iOS to reclaim the hardware from outside either queue's bookkeeping —
/// the signature of two things having briefly disagreed about who owned it,
/// not a crash.
///
/// The fix relies on one more fact: AVCaptureSession.startRunning() and
/// stopRunning() are both documented as BLOCKING calls — they don't return
/// until the session has actually started or stopped. So once both tabs'
/// work is funneled through this single serial queue, plain FIFO ordering is
/// enough: whichever tab's release job was enqueued first is GUARANTEED to
/// have fully released the camera — not merely begun to — before the other
/// tab's claim job, right behind it in the same queue, can even start. No
/// completion handlers or explicit handoff signalling needed.
let sharedCameraSessionQueue = DispatchQueue(label: "com.bodycam.camera.session", qos: .userInitiated)

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

/// Applies a zoom factor to the session's current video device, clamped to
/// what that specific device actually supports. Deliberately reads the clamp
/// from the device itself rather than a fixed range — hardware varies
/// widely, a single lens iPhone tops out far lower than a multi lens Pro
/// model — so the same call is correct on any of them without needing to
/// know in advance which camera is attached.
///
/// `onApplied` reports back the value that actually landed, not the one
/// requested, since a pinch gesture routinely asks for more zoom than the
/// device can give and the caller needs the real number for its on screen
/// readout.
/// Picks the best available camera for a position, so pinch-zoom's range
/// actually reflects what the hardware can do rather than being confined to
/// whatever a single lens allows.
///
/// `.builtInWideAngleCamera` names ONE physical lens — its own zoom range
/// bottoms out at 1x no matter the device, since there is no second lens to
/// optically switch to below that, and its reported max is pure digital crop
/// on that one sensor. A newer iPhone's 0.5x ultra-wide and its
/// optically-assisted telephoto reach only exist behind the VIRTUAL
/// multi-lens device types below, which is what actually reports a
/// minAvailableVideoZoomFactor under 1 and switches lenses under the hood as
/// videoZoomFactor crosses each one's threshold — the same device iOS's own
/// Camera app uses for its 0.5x/1x/3x row. Tried in order from most lenses to
/// fewest, since a Pro model supports every earlier case a non-Pro or
/// single-lens model does, and the loop just stops at whichever this
/// specific device actually has.
///
/// Front cameras never carry multiple lenses, so this always falls straight
/// through to plain wide-angle there.
func bestCaptureDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
    if position == .back {
        if let triple = AVCaptureDevice.default(.builtInTripleCamera, for: .video, position: .back) {
            return triple
        }
        if let dualWide = AVCaptureDevice.default(.builtInDualWideCamera, for: .video, position: .back) {
            return dualWide
        }
    }
    return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
}

func applyZoom(_ factor: CGFloat, session: AVCaptureSession?, on queue: DispatchQueue,
               onApplied: @escaping (CGFloat) -> Void) {
    guard let session else { return }
    queue.async {
        guard let device = session.inputs
            .compactMap({ $0 as? AVCaptureDeviceInput })
            .first(where: { $0.device.hasMediaType(.video) })?.device
        else { return }

        let clamped = min(max(factor, device.minAvailableVideoZoomFactor),
                          device.maxAvailableVideoZoomFactor)
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
        } catch {
            print("Zoom failed: \(error)")
        }
        DispatchQueue.main.async { onApplied(clamped) }
    }
}

/// Applies exposure compensation (EV), clamped to the device's own supported
/// range — Pro mode's brightness slider. Lets someone correct for a backlit
/// or high-contrast scene before recording starts, rather than fighting
/// whatever auto-exposure decides.
func applyExposureBias(_ bias: Float, session: AVCaptureSession?, on queue: DispatchQueue,
                       onApplied: @escaping (Float) -> Void) {
    guard let session else { return }
    queue.async {
        guard let device = session.inputs
            .compactMap({ $0 as? AVCaptureDeviceInput })
            .first(where: { $0.device.hasMediaType(.video) })?.device
        else { return }

        let clamped = min(max(bias, device.minExposureTargetBias),
                          device.maxExposureTargetBias)
        do {
            try device.lockForConfiguration()
            device.setExposureTargetBias(clamped, completionHandler: nil)
            device.unlockForConfiguration()
        } catch {
            print("Exposure bias failed: \(error)")
        }
        DispatchQueue.main.async { onApplied(clamped) }
    }
}

/// Reads the CURRENT device's actual exposure bias range, so Pro mode's
/// slider reflects real hardware limits rather than a fixed guess baked into
/// the UI. Most iPhones report something on the order of ±8, far wider than a
/// "comfortable everyday range" UI default — which matters for something
/// like a bright moon against a dark sky, where taming the highlight needs
/// far more negative compensation than an ordinary backlit-face shot would.
func currentExposureBiasRange(session: AVCaptureSession?, on queue: DispatchQueue,
                              onFetched: @escaping (ClosedRange<Float>) -> Void) {
    guard let session else { return }
    queue.async {
        guard let device = session.inputs
            .compactMap({ $0 as? AVCaptureDeviceInput })
            .first(where: { $0.device.hasMediaType(.video) })?.device
        else { return }
        let range = device.minExposureTargetBias...device.maxExposureTargetBias
        DispatchQueue.main.async { onFetched(range) }
    }
}

/// Freezes (or restores) focus and exposure at whatever they currently are —
/// Pro mode's AE/AF lock. A body cam moves and things constantly cross the
/// frame, and continuous auto focus/exposure re-hunts every time something
/// does; locking stops that mid-recording instability at the cost of no
/// longer adapting if the actual lighting changes.
func setAutoLock(_ locked: Bool, session: AVCaptureSession?, on queue: DispatchQueue) {
    guard let session else { return }
    queue.async {
        guard let device = session.inputs
            .compactMap({ $0 as? AVCaptureDeviceInput })
            .first(where: { $0.device.hasMediaType(.video) })?.device
        else { return }
        do {
            try device.lockForConfiguration()
            if locked {
                if device.isFocusModeSupported(.locked) { device.focusMode = .locked }
                if device.isExposureModeSupported(.locked) { device.exposureMode = .locked }
            } else {
                if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
                if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            }
            device.unlockForConfiguration()
        } catch {
            print("Auto lock toggle failed: \(error)")
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

/// Puts zoom, exposure bias, and focus/exposure mode back to neutral on
/// whatever device is currently attached.
///
/// Call this whenever a tab lets go of the camera (both ContentView and
/// PhotoCameraView do, in onDisappear), not just on flip. AVCaptureDevice.default(...)
/// does not hand back a fresh object per session — repeated calls return the
/// SAME physical camera every time, and videoZoomFactor/exposureTargetBias/
/// focusMode/exposureMode all live ON that device, not on the session or
/// input. Stopping a session does nothing to any of that, so a manual
/// adjustment made in one tab would otherwise still be sitting on the
/// hardware the next time the other tab claims it — while that tab's OWN
/// zoom readout, EV slider, and lock button all show neutral, since each
/// tab's @State only knows what IT set, never what was left behind.
func resetManualCameraAdjustments(session: AVCaptureSession?, on queue: DispatchQueue) {
    guard let session else { return }
    queue.async {
        guard let device = session.inputs
            .compactMap({ $0 as? AVCaptureDeviceInput })
            .first(where: { $0.device.hasMediaType(.video) })?.device
        else { return }

        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = 1.0
            device.setExposureTargetBias(0, completionHandler: nil)
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
        } catch {
            print("Resetting manual camera adjustments failed: \(error)")
        }
    }
}

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    /// When false, the preview connection is switched off so no frames are
    /// delivered or composited. Used while the screen is dimmed, where the
    /// preview is hidden behind a black overlay and rendering it is pure waste.
    var isPreviewActive: Bool = true
    /// Receives a normalized device point (0...1) when the user taps to focus.
    var onFocusTap: ((CGPoint) -> Void)? = nil
    /// Receives the RAW requested zoom factor as a pinch progresses — not yet
    /// clamped to the device's own range, since PreviewUIView has no queue to
    /// safely read that from. The caller clamps and applies via applyZoom(),
    /// same division of responsibility as onFocusTap.
    var onPinchZoom: ((CGFloat) -> Void)? = nil

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.applyCurrentOrientation()
        view.onFocusTap = onFocusTap
        view.onPinchZoom = onPinchZoom
        view.setPreviewActive(isPreviewActive)
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.onFocusTap = onFocusTap
        uiView.onPinchZoom = onPinchZoom
        uiView.setPreviewActive(isPreviewActive)
    }

    class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        var onFocusTap: ((CGPoint) -> Void)?
        var onPinchZoom: ((CGFloat) -> Void)?
        private weak var focusIndicator: UIView?
        /// The device's own zoom factor at the moment a pinch begins, so the
        /// gesture's scale (always relative to ITS OWN start, resetting to 1
        /// on every new pinch) can be turned into an absolute factor.
        private var pinchStartZoom: CGFloat = 1.0

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
            addGestureRecognizer(
                UIPinchGestureRecognizer(target: self, action: #selector(handlePinchZoom(_:)))
            )
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }

        /// Switches only the PREVIEW connection. A capture session keeps a
        /// separate connection per output, so this leaves the movie-file output
        /// (and therefore any recording in progress) completely untouched.
        /// Deliberately not `previewLayer.session = nil`, which tears down the
        /// layer's session association and can interrupt an active recording.
        func setPreviewActive(_ active: Bool) {
            guard let connection = previewLayer.connection,
                  connection.isEnabled != active else { return }
            connection.isEnabled = active
            // The orientation is applied to the connection, so re-assert it on
            // the way back rather than trusting whatever it held while off.
            if active { applyCurrentOrientation() }
        }

        @objc private func handleFocusTap(_ recognizer: UITapGestureRecognizer) {
            guard let onFocusTap else { return }
            let viewPoint = recognizer.location(in: self)
            let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: viewPoint)
            showFocusIndicator(at: viewPoint)
            onFocusTap(devicePoint)
        }

        // UIPinchGestureRecognizer's scale is always relative to where THIS
        // pinch started (resets to 1 on every new touch-down), not to the
        // device's actual zoom — so the device's real current factor is
        // captured once at .began and the running scale is applied on top of
        // it, rather than ever reading scale as an absolute value.
        @objc private func handlePinchZoom(_ recognizer: UIPinchGestureRecognizer) {
            guard let onPinchZoom else { return }
            switch recognizer.state {
            case .began:
                pinchStartZoom = (previewLayer.session?.inputs
                    .compactMap { $0 as? AVCaptureDeviceInput }
                    .first { $0.device.hasMediaType(.video) }?.device.videoZoomFactor) ?? 1.0
            case .changed:
                onPinchZoom(pinchStartZoom * recognizer.scale)
            default:
                break
            }
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
