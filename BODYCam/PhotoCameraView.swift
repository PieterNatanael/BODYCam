import SwiftUI
import AVFoundation
import AudioToolbox

// MARK: - Photo Quality

enum PhotoQuality: String, CaseIterable {
    case low  = "LOW"
    case med  = "MED"
    case high = "HIGH"
    case max  = "MAX"

    /// Spatial scale applied before JPEG encoding.
    /// LOW = 0.5 → ¼ the pixels → dramatically smaller file even before compression.
    /// Max's resolution boost happens earlier, at capture (see
    /// PhotoCameraView.capturePhoto), so no extra scale is needed here.
    var spatialScale: CGFloat {
        switch self {
        case .low:  return 0.5
        case .med:  return 1.0
        case .high: return 1.0
        case .max:  return 1.0
        }
    }

    /// JPEG compression factor (0 = smallest/worst, 1 = largest/best).
    var jpegCompression: CGFloat {
        switch self {
        case .low:  return 0.25
        case .med:  return 0.65
        case .high: return 0.92
        case .max:  return 0.95
        }
    }
}

// MARK: - Shutter tick

/// The soft tick played in place of the system shutter, which is suppressed
/// in PhotoCaptureDelegate.willCapturePhotoFor.
///
/// Bundled as a file rather than borrowing one of iOS's built in system sound
/// ids: AudioServicesPlaySystemSound returns nothing and does nothing at all
/// when handed an id the OS doesn't have, so there is no way to detect a
/// missing sound and fall back to another one. A file that ships inside the
/// app cannot go missing, and sounds identical on every iOS version.
///
/// Played through system sound services, the same channel the shutter itself
/// uses. That matters: it means the volume drop around each capture, which
/// only moves the MEDIA level, cannot mute this either. It follows the ring
/// volume and the silent switch, so a phone set to silent stays silent.
enum ShutterTick {
    /// Registered once and reused. Re-creating the sound id per capture would
    /// leak a system sound object on every shot.
    private static let soundID: SystemSoundID? = {
        guard let url = Bundle.main.url(forResource: "ShutterTick", withExtension: "caf") else {
            return nil
        }
        var id: SystemSoundID = 0
        guard AudioServicesCreateSystemSoundID(url as CFURL, &id) == kAudioServicesNoError else {
            return nil
        }
        return id
    }()

    static func play() {
        guard let soundID = soundID else { return }
        AudioServicesPlaySystemSound(soundID)
    }
}

// MARK: - Photo Capture Delegate

final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, ObservableObject {
    /// One in-flight request's own quality and callbacks. Tracked per request,
    /// rather than as shared mutable properties on the delegate, because the
    /// shutter button no longer stays disabled for the whole save pipeline —
    /// a second tap can now fire while the first photo is still being scaled,
    /// stamped, and written, and each has to be finished with the settings it
    /// was actually taken with, not whatever the delegate's properties were
    /// last overwritten to.
    private struct PendingCapture {
        let quality: PhotoQuality
        let onShutterFired: () -> Void
        let onFinish: (Bool) -> Void
    }

    /// Keyed by AVCapturePhotoSettings.uniqueID, which AVFoundation carries
    /// through to both delegate callbacks below for the same request, so a
    /// result can always be matched back to the request that produced it —
    /// even when several are in flight at once. Access goes through
    /// stateQueue because these delegate methods are called on an arbitrary
    /// AVFoundation-owned queue, not necessarily the same one twice in a row,
    /// so a plain dictionary would race under overlapping captures.
    private var pending: [Int64: PendingCapture] = [:]
    private let stateQueue = DispatchQueue(label: "PhotoCaptureDelegate.pending")

    /// Called right before output.capturePhoto(with:delegate:), so this
    /// request's identity is registered before AVFoundation can possibly call
    /// back about it.
    func beginCapture(settings: AVCapturePhotoSettings, quality: PhotoQuality,
                      onShutterFired: @escaping () -> Void,
                      onFinish: @escaping (Bool) -> Void) {
        stateQueue.sync {
            pending[settings.uniqueID] = PendingCapture(
                quality: quality, onShutterFired: onShutterFired, onFinish: onFinish)
        }
    }

    /// Called by AVFoundation immediately before the shutter fires, which is
    /// also the moment the system plays the shutter sound. Disposing the sound
    /// object here stops it before it is heard.
    ///
    /// This is needed because lowering the system volume does NOT silence the
    /// shutter: the MPVolumeView slider VolumeButtonObserver drives controls
    /// the MEDIA playback volume, while the shutter is played through system
    /// sound services, the same channel as keyboard clicks. They are separate
    /// levels, so the volume drop around each capture never touched it.
    ///
    /// 1108 is the shutter's system sound id. If a future iOS changes that id
    /// or the behaviour, this quietly stops working and the sound comes back —
    /// it cannot fail in a way that breaks capture.
    ///
    /// Note that iPhones sold in Japan and South Korea enforce the shutter
    /// sound below this level, and it will still play there.
    ///
    /// This is also the earliest reliable signal that THIS capture's shutter
    /// has actually fired, which is what tells the button it can pop back up
    /// — well before the photo has finished saving.
    func photoOutput(_ output: AVCapturePhotoOutput,
                     willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        AudioServicesDisposeSystemSoundID(1108)
        let entry = stateQueue.sync { pending[resolvedSettings.uniqueID] }
        DispatchQueue.main.async { entry?.onShutterFired() }
    }

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard let entry = stateQueue.sync(execute: {
            pending.removeValue(forKey: photo.resolvedSettings.uniqueID)
        }) else {
            // Should never happen — every capture is registered in
            // beginCapture before AVFoundation can call back about it, and
            // AVFoundation guarantees the same uniqueID on both callbacks for
            // one request. If it somehow does, there is no request left to
            // report a result to.
            return
        }
        let quality = entry.quality
        let onFinish = entry.onFinish

        guard error == nil,
              let rawData = photo.fileDataRepresentation(),
              let rawImage = UIImage(data: rawData) else {
            DispatchQueue.main.async { onFinish(false) }
            return
        }

        // --- Post-process on the background thread AVFoundation already gave us ---

        // 1. Scale down if needed (LOW = 50 % linear → 25 % of pixels)
        let scale = quality.spatialScale
        var processed: UIImage
        if scale < 1.0 {
            let targetSize = CGSize(width:  rawImage.size.width  * scale,
                                    height: rawImage.size.height * scale)
            // scale = 1 for the same reason as applyDateStamp below, and here
            // it also fixes the result: the renderer's default scale of 3 was
            // making LOW render at 3x the target, i.e. 1.5x the ORIGINAL
            // linear size — the opposite of the "50% linear, 25% of the
            // pixels" this block says it does, and a bigger file than High.
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            format.opaque = true
            let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
            processed = renderer.image { _ in
                rawImage.draw(in: CGRect(origin: .zero, size: targetSize))
            }
        } else {
            processed = rawImage
        }

        // 1.5. Burn a visible date stamp in, if the user opted in. Off by
        // default and read straight from UserDefaults rather than an
        // @AppStorage — this class isn't a View and can't hold one.
        if UserDefaults.standard.bool(forKey: "ShowDateStamp") {
            processed = PhotoCaptureDelegate.applyDateStamp(to: processed)
        }

        // 2. Re-encode as JPEG with the tier's compression factor
        guard let jpeg = processed.jpegData(compressionQuality: quality.jpegCompression) else {
            DispatchQueue.main.async { onFinish(false) }
            return
        }

        // 3. Save to the app's own Documents directory — same place video
        // recordings go. This shows up in the in-app Gallery tab, where the
        // user can choose to save it to Photos or share it, same as video.
        let timestamp = Date().timeIntervalSince1970
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("photo_\(timestamp).jpg")
        do {
            try jpeg.write(to: url)
            DispatchQueue.main.async { onFinish(true) }
        } catch {
            DispatchQueue.main.async { onFinish(false) }
        }
    }

    /// Draws the capture date/time and "LBC" into the bottom-right corner,
    /// directly onto the pixels — permanent, unlike EXIF metadata, which is
    /// invisible unless someone opens the file's info panel. That's the whole
    /// point of this feature over what the file already carries for free.
    static func applyDateStamp(to image: UIImage) -> UIImage {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        // Deliberately never localized: a stamp meant to travel with the file
        // anywhere it's shared should read the same regardless of whoever
        // eventually views it, the same reasoning as the app's own name
        // staying fixed elsewhere.
        let text = "\(formatter.string(from: Date())) · LBC"

        // scale = 1 is essential, not a detail. UIGraphicsImageRenderer
        // defaults its format scale to UIScreen.main.scale (3 on modern
        // iPhones), so rendering a 3024x4032 photo would allocate a
        // 9072x12096 bitmap — around 110 megapixels and hundreds of MB — to
        // stamp a line of text. That is what made stamped photos take
        // seconds to save, and the memory spike is the likeliest reason the
        // stamp silently failed to appear on the larger portrait renders.
        // The photo's pixels are already the output; nothing here needs
        // rasterizing at display density.
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))

            // Same sizing rule as the video stamp, shared rather than
            // duplicated so the two can't drift into looking like different
            // features. Photos are high resolution enough that the width term
            // rarely binds here, but keeping one rule means a future change
            // lands on both.
            let fontSize = VideoCaptureDelegate.stampFontSize(for: image.size)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .right
            let shadow = NSShadow()
            shadow.shadowColor = UIColor.black.withAlphaComponent(0.9)
            shadow.shadowBlurRadius = 3
            shadow.shadowOffset = .zero
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph,
                .shadow: shadow
            ]

            let margin = image.size.width * 0.025
            let lineHeight = fontSize * 1.4
            let textRect = CGRect(x: margin, y: image.size.height - margin - lineHeight,
                                  width: image.size.width - margin * 2, height: lineHeight)
            (text as NSString).draw(in: textRect, withAttributes: attributes)
        }
    }
}

// MARK: - PhotoCameraView

struct PhotoCameraView: View {

    // MARK: - Session

    @State private var captureSession: AVCaptureSession?
    @State private var photoOutput: AVCapturePhotoOutput?
    @StateObject private var captureDelegate  = PhotoCaptureDelegate()
    @StateObject private var volumeObserver   = VolumeButtonObserver()

    /// ALL AVCaptureSession operations must run on a dedicated serial queue.
    ///
    /// This USED to be its own separate queue from ContentView's. Now points
    /// at the queue shared with it instead — see sharedCameraSessionQueue's
    /// own comment in CameraPreviewView.swift for why two independent queues
    /// here was a real, confirmed bug (a frozen camera after a fast
    /// Video → Photo → Video switch right after stopping a recording), not
    /// just a theoretical one.
    private static let sessionQueue = sharedCameraSessionQueue

    // MARK: - UI State

    @AppStorage("SelectedPhotoQuality") private var quality: PhotoQuality = .high
    /// The rule-of-thirds composition grid, shown over the preview in every
    /// display mode, not just Pro — Pro just happens to be where the one
    /// on-screen toggle button lives. Shared across tabs via AppStorage — a
    /// preference about how you like to frame shots, not something tied to
    /// one tab's own state the way zoom/exposure are. Defaults on: it is a
    /// framing aid, not a destructive or surprising change to what gets
    /// captured, so there is no real downside to a new user having it from
    /// the start.
    @AppStorage("ShowGridLines") private var showGridLines: Bool = true
    /// Circle mode's interface is locked to portrait (see AppDelegate), so
    /// this tracks the phone's raw physical rotation separately, purely to
    /// decide which way its control icons should turn to stay upright —
    /// never used for layout, which is what stays still.
    @State private var deviceOrientation: UIDeviceOrientation = UIDevice.current.orientation
    @State private var isUsingFront     = false
    /// Mirrors the video device's own videoZoomFactor for the on screen
    /// readout. Reset to 1 on flip, since a freshly attached device always
    /// starts there regardless of what the previous camera was zoomed to.
    @State private var zoomFactor: CGFloat = 1.0
    /// Pro mode's exposure compensation and AE/AF lock state. Both reset on
    /// flip for the same reason zoomFactor does: a freshly attached device
    /// always starts at 0 bias / continuous auto, regardless of what the
    /// previous camera was set to.
    @State private var exposureBias: Float = 0
    @State private var isAutoLocked = false
    /// The slider's actual bounds, read from whatever camera is currently
    /// attached rather than a fixed guess — real hardware commonly supports
    /// something like ±8, far past what a "typical scene" default would
    /// suggest. -2...2 is a starting placeholder only, replaced the moment a
    /// device is available; a taming-the-moon shot needs the true range.
    @State private var exposureBiasRange: ClosedRange<Float> = -2...2
    @State private var isCapturing      = false
    @State private var saveStatus: SaveStatus?
    /// Drives the shutter blink over the preview. Black rather than white,
    /// matching the built in Camera app: it reads as a shutter closing, and
    /// white would blow out the viewfinder's own dark UI.
    @State private var shutterFlash     = false
    /// Held rather than created per capture so it can be kept prepared, and so
    /// repeated shots reuse one warmed generator.
    @State private var hapticGenerator  = UIImpactFeedbackGenerator(style: .light)
    @State private var isScreenDimmed   = false
    @State private var savedBrightness: CGFloat = UIScreen.main.brightness
    @State private var showAppSettingsSheet = false
    @AppStorage("CameraDisplayMode") private var displayModeRaw: String = CameraDisplayMode.saveBattery.rawValue
    private var displayMode: CameraDisplayMode { CameraDisplayMode(rawValue: displayModeRaw) ?? .saveBattery }
    /// .zero outside Circle mode — every other mode lets the interface
    /// itself rotate, so its icons never need to turn independently.
    private var circleIconRotation: Angle {
        displayMode == .circle ? iconRotationAngle(for: deviceOrientation) : .zero
    }
    @AppStorage("AppTheme") private var appThemeRaw: String = AppTheme.tropical.rawValue
    private var appTheme: AppTheme { AppTheme(rawValue: appThemeRaw) ?? .normal }
    // Simple and Tactical share the same flat/no-gradient/sharp-corner "bones";
    // only their accent colors (and the preview's corner-bracket treatment) differ.
    private var isFlatTheme: Bool { appTheme.isFlat }
    private var previewDecoration: PreviewFrameDecoration { appTheme.previewDecoration }

    // MARK: - Theme accent palette (defined once on AppTheme)

    private var flipAccent: Color { appTheme.flipAccent }
    private var dimAccent: Color { appTheme.dimAccent }
    private var settingsAccent: Color { appTheme.settingsAccent }
    private var shutterAccent: Color { appTheme.recordAccent }
    private var previewAccent: Color { appTheme.previewAccent }

    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @State private var showPaywall = false

    enum SaveStatus { case saving, success, failure }

    // MARK: - Adaptive layout

    private var isCompact: Bool        { UIScreen.main.bounds.height < 700 }
    private var btnFrame: CGFloat      { isCompact ? 100 : 120 }
    private var btnOuter: CGFloat      { isCompact ? 74  : 90  }
    private var btnInner: CGFloat      { isCompact ? 56  : 70  }
    private var btnTickOffset: CGFloat { isCompact ? 44  : 54  }
    private var bottomPad: CGFloat     { isCompact ? 12  : 36  }

    // Fixed size (not "fit remaining space") so the preview card renders at the
    // exact same size on this tab and the Video tab, regardless of how much
    // vertical space each tab's other elements (status label, toolbar, etc.) use.
    // Clamped against screen height so it can't overflow on the smallest devices
    // (CameraPreviewView uses .resizeAspectFill, so a shorter frame just crops
    // the feed slightly rather than breaking layout).
    // UIScreen.main.bounds always reports the device's native PORTRAIT
    // dimensions and never rotates with the interface — using it directly
    // left the card sized as if the phone were always upright, so turning
    // the phone sideways made it small and portrait-shaped inside a now-wide
    // landscape screen. isLandscapeInterface + effectiveScreenSize correct
    // for that; Normal mode never had this problem because it already sizes
    // itself from GeometryReader's measured space instead of UIScreen.
    private var isLandscapeInterface: Bool {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
            .interfaceOrientation.isLandscape ?? false
    }
    private var effectiveScreenSize: CGSize {
        let native = UIScreen.main.bounds.size
        return isLandscapeInterface ? CGSize(width: native.height, height: native.width) : native
    }

    private var previewCardWidth: CGFloat {
        // In landscape the card's width is DERIVED from its height (below)
        // rather than the other way around, since landscape's binding
        // constraint is vertical space, not horizontal.
        isLandscapeInterface ? previewCardHeight * 4 / 3 : effectiveScreenSize.width - 48
    }
    private var previewCardHeight: CGFloat {
        if isLandscapeInterface {
            // Landscape has far less vertical room to begin with, and almost
            // none of it goes to chrome — just the thin top strip and the
            // shutter row itself — so the reserve here is much smaller than
            // portrait's.
            let reserved: CGFloat = isCompact ? 90 : 110
            return effectiveScreenSize.height - reserved
        }
        let natural: CGFloat = (effectiveScreenSize.width - 48) * 4 / 3
        let reserved: CGFloat = isCompact ? 260 : 300
        return min(natural, effectiveScreenSize.height - reserved)
    }

    /// Circle mode's preview diameter — the largest circle that fits the same
    /// reserved chrome space as the Save Battery card, in EITHER orientation.
    /// Unlike previewCardWidth/Height, which derive one dimension from the
    /// other via a fixed 4:3 ratio, a circle needs an equal width and height,
    /// so this takes whichever of the two available constraints (horizontal
    /// room, vertical room) is actually tighter right now.
    private var previewCircleDiameter: CGFloat {
        let maxWidth = effectiveScreenSize.width - 48
        let reserved: CGFloat = isLandscapeInterface
            ? (isCompact ? 90 : 110)
            : (isCompact ? 260 : 300)
        let maxHeight = effectiveScreenSize.height - reserved
        return min(maxWidth, maxHeight)
    }

    /// Reaches the screen's corners, the farthest a centered gradient ever has
    /// to travel, so it reads as fully faded to black there rather than
    /// stopping short on larger devices.
    private var screenGlowRadius: CGFloat {
        let size = UIScreen.main.bounds.size
        return sqrt(size.width * size.width + size.height * size.height) / 2
    }

    // Simple/Tactical: sharp corners + a bold flat accent border (or corner
    // brackets for Tactical), "frame as object" rather than the Normal theme's
    // subtle rounded card-with-depth look.
    private var previewCornerRadius: CGFloat { isFlatTheme ? 0 : 10 }
    private var previewBorderColor: Color { isFlatTheme ? previewAccent : Color(white: 0.3) }
    private var previewBorderWidth: CGFloat { appTheme.previewBorderWidth }

    // Tactical gets a viewfinder-style corner-bracket reticle instead of a
    // plain stroked rectangle around the preview frame.
    @ViewBuilder
    private func previewBorderOverlay(radius: CGFloat, color: Color, width: CGFloat,
                                       decoration: PreviewFrameDecoration) -> some View {
        switch decoration {
        case .brackets:
            CornerBrackets(length: 22).stroke(color, lineWidth: width)
        case .web:
            SpiderWebCorners(radius: 64).stroke(color, lineWidth: width)
        case .border:
            RoundedRectangle(cornerRadius: radius).stroke(color, lineWidth: width)
        }
    }

    @ViewBuilder
    private var gridLinesOverlay: some View {
        // Available in every mode, Circle included — the call site clips
        // this to the same shape as the preview itself (see sharedPreviewLayer),
        // so in Circle mode the lines are cut off cleanly at the circle's
        // edge instead of running past it into the corners the circle cuts
        // away.
        if showGridLines {
            RuleOfThirdsGrid()
                .stroke(Color.white.opacity(0.6), lineWidth: 1)
                .allowsHitTesting(false)
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            background

            sharedPreviewLayer

            // Top chrome differs by mode, but statusLabel + shutterRow are a
            // single shared view below — previously each mode had its own copy,
            // and small layout differences between them caused it to shift
            // position (and clip behind the tab bar) when switching modes.
            VStack(spacing: 0) {
                topChrome
                Spacer()
                statusLabel
                Spacer().frame(height: isCompact ? 6 : 10)
                if displayMode == .pro {
                    proControlsPanel
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)
                }
                shutterRow
                    .padding(.bottom, bottomPad)
            }
        }
        .sheet(isPresented: $showAppSettingsSheet) {
            SettingsView()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView().environmentObject(subscriptionManager)
        }
        .onAppear {
            // Needed so UIDevice.current.orientation is actually kept up to
            // date — capturePhoto() reads it to set the shot's orientation
            // so landscape photos come out right-side-up.
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            if let session = captureSession {
                // Returning from another tab — restart the session
                PhotoCameraView.sessionQueue.async {
                    if !session.isRunning { session.startRunning() }
                }
            } else {
                setupCaptureSession()
            }
            volumeObserver.start { self.capturePhoto() }
            // Warms the Taptic Engine so the first shutter of the session taps
            // as promptly as the rest. Without this the hardware idles down and
            // the very first impact can land noticeably late.
            hapticGenerator.prepare()
        }
        .onDisappear {
            restoreBrightness()
            volumeObserver.stop()
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
            // Release the camera so the Video tab can reclaim it
            let session = captureSession
            PhotoCameraView.sessionQueue.async { session?.stopRunning() }
            // See ContentView's identical call for why this is needed beyond
            // stopRunning: zoom/exposure bias/focus mode live on the shared
            // physical device object, not on this (stopped) session.
            resetManualCameraAdjustments(session: session, on: PhotoCameraView.sessionQueue)
            // The readouts also need to go back to neutral here, not just the
            // device — this tab's own @State persists across a tab switch, so
            // without this, returning later would show a stale value that no
            // longer matches the hardware this just put back to neutral.
            zoomFactor = 1.0
            exposureBias = 0
            isAutoLocked = false
        }
        // Reconfigure the moment the setting changes, while the user is still
        // in Settings — not on the next shutter press, where the resulting
        // session reconfiguration would race the capture itself.
        .onChange(of: quality) { _ in
            applyPhotoDimensions()
        }
        // Settings is presented as a sheet over this view, not a replacement
        // for it, so switching display modes there does NOT trigger
        // onDisappear — the only other place Pro's settings get reset.
        // Without this, leaving Pro mode by switching straight to another
        // mode (never leaving the tab) left whatever exposure bias / AE-AF
        // lock Pro set still sitting on the physical camera, silently
        // affecting the mode switched to.
        //
        // Deliberately narrower than resetManualCameraAdjustments: this only
        // clears the two things Pro mode itself exposes. Zoom is a separate,
        // intentionally persistent control shared across every display mode
        // (see the zoom button), and resetting it here on every mode switch
        // would undo a zoom the user set in Normal mode the moment they so
        // much as glanced at Pro mode.
        .onChange(of: displayModeRaw) { _ in
            applyExposureBias(0, session: captureSession, on: PhotoCameraView.sessionQueue) { applied in
                exposureBias = applied
            }
            setAutoLock(false, session: captureSession, on: PhotoCameraView.sessionQueue)
            isAutoLocked = false
            // AppDelegate.supportedInterfaceOrientationsFor only gets
            // consulted again when something asks iOS to re-check — this is
            // that ask, needed both entering Circle mode (snaps a currently
            // landscape interface back to portrait immediately) and leaving
            // it (frees the interface to rotate again without waiting for
            // the next physical rotation to prompt a check on its own).
            UIViewController.attemptRotationToDeviceOrientation()
        }
        // RootView → PhotoCameraView: restore brightness when user taps overlay
        .onReceive(NotificationCenter.default.publisher(for: .userRequestedWake)) { _ in
            wakeScreen()
        }
        // Backs circleIconRotation. isValidInterfaceOrientation filters out
        // .faceUp/.faceDown/.unknown — frequent, completely normal readings
        // while actually holding and using the phone, which would otherwise
        // snap every icon back to .zero any time it's set down or tilted
        // flat, only to snap again the moment a real orientation is read.
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            let new = UIDevice.current.orientation
            guard new.isValidInterfaceOrientation else { return }
            deviceOrientation = new
        }
        // Screen brightness is a system-wide setting that survives the app, so
        // backgrounding while dimmed would otherwise leave the user's phone at
        // 1% until they fixed it themselves.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            restoreBrightness()
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var background: some View {
        if isFlatTheme {
            // Not normal rather than == .saveBattery specifically: this tab has
            // no separate Yapping treatment, so any non-normal mode already
            // renders the same compact card the glow is meant to sit behind.
            if let glow = appTheme.cameraBackgroundGlow, displayMode != .normal {
                // startRadius reaches roughly the card's own edge — the card
                // covers the true center, so a small startRadius meant the
                // gradient had already faded well past full strength by the
                // time it emerged from behind the card, reading as weak.
                RadialGradient(colors: [glow, .black],
                               center: .center,
                               startRadius: (displayMode == .circle ? previewCircleDiameter : previewCardWidth) / 2,
                               endRadius: screenGlowRadius)
                    .ignoresSafeArea()
            } else {
                Color.black.ignoresSafeArea()
            }
        } else {
            ZStack {
                Image("pattern1").resizable().ignoresSafeArea()
                LinearGradient(
                    colors: [.black, Color(#colorLiteral(red: 0.476, green: 0.476, blue: 0.476, alpha: 1))],
                    startPoint: .top, endPoint: .bottom
                ).opacity(0.8).ignoresSafeArea()
            }
        }
    }

    // MARK: - Top chrome (differs by mode)

    @ViewBuilder
    private var topChrome: some View {
        if displayMode == .normal {
            HStack {
                Spacer()
                if !subscriptionManager.isUnlocked {
                    goProBadge
                }
            }
            .padding(.top, 8)
            .padding(.trailing)
        } else {
            toolbar
        }
    }

    private var toolbar: some View {
        HStack {
            // The one spot in the top strip with genuinely free space:
            // Normal and Yapping-equivalent modes fill or share this area,
            // and Save Battery has nothing of its own to put here — Pro
            // mode does.
            if displayMode == .pro {
                gridToggleButton
                    .padding(.leading)
            }

            Spacer()
            if !subscriptionManager.isUnlocked {
                goProBadge
                    .padding(.trailing)
            }
        }
        .padding(.vertical, 8)
        .frame(height: isCompact ? 34 : 42)
    }

    /// Lives in the top strip rather than the bottom panel with exposure/lock
    /// — that panel is about the moment right before or during a capture,
    /// while grid lines are a standing composition preference someone sets
    /// once and leaves alone, closer in spirit to the top strip's other
    /// persistent chrome.
    private var gridToggleButton: some View {
        Button(action: { showGridLines.toggle() }) {
            Image(systemName: "grid")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(showGridLines ? Color(red: 1.0, green: 0.85, blue: 0.4) : Color(white: 0.6))
                .frame(width: 30, height: 30)
                .background(
                    Circle().fill(Color.black.opacity(0.35))
                )
        }
    }

    private var goProBadge: some View {
        Button(action: { showPaywall = true }) {
            HStack(spacing: 5) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12))
                Text("PREMIUM")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1)
            }
            .foregroundColor(Color(white: 0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(white: 0.2))
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(white: 0.45), lineWidth: 1)
                }
            )
        }
    }

    // MARK: - Shared preview layer
    //
    // Save Battery and Normal mode used to each build their own CameraPreviewView,
    // so switching modes destroyed one AVCaptureVideoPreviewLayer and created another —
    // reattaching a preview layer to a running session is expensive and was the cause
    // of the visible stall/lag on mode switch. This single instance stays in the same
    // position in the view tree across both modes; only its size/corner/border VALUES
    // change, so SwiftUI updates it in place instead of tearing it down.
    private var sharedPreviewLayer: some View {
        // GeometryReader here measures the actual safe content rectangle (the
        // same area the tab bar already keeps clear). The outer container below
        // is pinned to exactly that size — this is what keeps the shutter row
        // (a sibling in `body`) from being dragged around by anything that
        // happens inside here. The CameraPreviewView itself, in Normal mode, is
        // given an EXPLICITLY larger frame (safe size + real top/bottom safe-area
        // insets) plus ignoresSafeArea, so it overflows past this pinned
        // container and bleeds under the notch and tab bar — without changing
        // the container's own reported size.
        //
        // Centering an oversized view distributes the overflow evenly on both
        // sides, but the top inset (status bar/notch) and bottom inset (tab bar)
        // are rarely equal — so a plain centered overflow undershoots one edge
        // and overshoots the other. The vertical offset below corrects for that,
        // so the bleed lands exactly at the top and exactly at the tab bar.
        GeometryReader { geo in
            let isNormal = displayMode == .normal
            let isCircle = displayMode == .circle
            let topInset = geo.safeAreaInsets.top
            let bottomInset = geo.safeAreaInsets.bottom
            let w: CGFloat = isNormal
                ? geo.size.width + geo.safeAreaInsets.leading + geo.safeAreaInsets.trailing
                : isCircle ? previewCircleDiameter : previewCardWidth
            let h: CGFloat = isNormal
                ? geo.size.height + topInset + bottomInset
                : isCircle ? previewCircleDiameter : previewCardHeight
            let verticalOffset: CGFloat = isNormal ? (bottomInset - topInset) / 2 : 0
            // Half the diameter, not previewCornerRadius's small rounded-rect
            // value — SwiftUI's cornerRadius (and RoundedRectangle's own
            // cornerRadius in previewBorderOverlay's .border case) both clamp
            // to half the shorter side, so on a perfectly square frame this
            // is exactly what turns the existing rounded-rect machinery into
            // a true circle, with no new shape code needed anywhere.
            let radius: CGFloat = isNormal ? 0 : isCircle ? previewCircleDiameter / 2 : previewCornerRadius
            let borderColor: Color = isNormal ? Color.clear : previewBorderColor
            let borderWidth: CGFloat = isNormal ? 0 : previewBorderWidth
            let placeholderFill: Color = (isFlatTheme || isNormal) ? Color.black : Color(white: 0.05)
            let accentColor: Color = isFlatTheme ? previewAccent : Color(white: 0.2)
            // Forced to .border regardless of theme: Tactical's brackets and
            // Spider's corner webs both assume a rectangular frame with real
            // corners to sit in, which a circle doesn't have — a plain
            // circular stroke is the only frame treatment that makes sense
            // here, the same reasoning Normal already gets its own override.
            let decoration: PreviewFrameDecoration = (isNormal || isCircle) ? .border : previewDecoration

            ZStack {
                if let session = captureSession {
                    // Tapping focuses (and re-meters exposure) rather than
                    // toggling the preview. Battery saving is the dim-screen
                    // button's job — it kills the backlight, which dwarfs the
                    // preview layer's own draw cost.
                    // isPreviewActive is bound to the dim state rather than
                    // toggled imperatively, so every route back out of dim
                    // re-enables the preview automatically — there's no path
                    // that can leave it stuck off.
                    CameraPreviewView(
                        session: session,
                        isPreviewActive: !isScreenDimmed,
                        onFocusTap: { devicePoint in
                            applyTapToFocus(session: captureSession,
                                            devicePoint: devicePoint,
                                            on: PhotoCameraView.sessionQueue)
                        },
                        onPinchZoom: { requested in
                            applyZoom(requested, session: captureSession, on: PhotoCameraView.sessionQueue) { applied in
                                zoomFactor = applied
                            }
                        }
                    )
                    .frame(width: w, height: h)
                    .cornerRadius(radius)
                    .overlay(
                        previewBorderOverlay(radius: radius, color: borderColor,
                                              width: borderWidth, decoration: decoration)
                    )
                    // clipShape here, matching the same radius the preview
                    // itself is cut to, is what makes the grid safe to show
                    // in every mode including Circle: in the rectangular
                    // modes this radius is small and the grid's own lines
                    // already terminate at the frame's edge, so it clips
                    // nothing new — but in Circle mode it cuts the grid's
                    // straight edge-to-edge lines off cleanly at the circle's
                    // boundary, instead of letting them run into the corners
                    // the circle itself cuts away.
                    .overlay(gridLinesOverlay.clipShape(RoundedRectangle(cornerRadius: radius)))
                    // Applied here rather than over the whole screen so the
                    // blink lands exactly on the viewfinder in every display
                    // mode, picking up the same corner radius and full bleed
                    // geometry as the preview itself.
                    .overlay(
                        RoundedRectangle(cornerRadius: radius)
                            .fill(Color.black)
                            .opacity(shutterFlash ? 1 : 0)
                            .allowsHitTesting(false)
                    )
                    .offset(y: verticalOffset)
                    .ignoresSafeArea(.all, edges: isNormal ? .all : [])
                }

                // Shown only until the capture session is ready. The preview is
                // never user-hidden any more, so this is purely a loading state.
                if captureSession == nil {
                    ZStack {
                        RoundedRectangle(cornerRadius: radius)
                            .fill(placeholderFill)
                            .overlay(
                                previewBorderOverlay(radius: radius, color: borderColor,
                                                      width: borderWidth, decoration: decoration)
                            )
                        VStack(spacing: 10) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: isNormal ? 46 : 38))
                                .foregroundColor(accentColor)
                            Text("STARTING CAMERA")
                                .font(.system(size: isNormal ? 12 : 10, weight: .bold, design: .monospaced))
                                .foregroundColor(accentColor)
                                .tracking(isNormal ? 3 : 2)
                        }
                    }
                    .frame(width: w, height: h)
                    .offset(y: verticalOffset)
                    .ignoresSafeArea(.all, edges: isNormal ? .all : [])
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    @ViewBuilder
    private var dimButton: some View {
        if isFlatTheme {
            Button(action: toggleDim) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.black)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(dimAccent, lineWidth: 2))
                        .frame(width: 44, height: 44)
                    Image(systemName: isScreenDimmed ? "moon.fill" : "moon")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(isScreenDimmed ? dimAccent.opacity(0.4) : dimAccent)
                }
            }
        } else {
            Button(action: toggleDim) {
                ZStack {
                    Circle()
                        .fill(isScreenDimmed ? Color(white: 0.04) : Color(white: 0.14))
                        .overlay(
                            Circle().stroke(isScreenDimmed ? Color(white: 0.15) : Color(white: 0.3), lineWidth: 1)
                        )
                        .frame(width: 44, height: 44)
                        .shadow(color: .black.opacity(0.4), radius: 3, x: 1, y: 2)
                    Image(systemName: isScreenDimmed ? "moon.fill" : "moon")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(isScreenDimmed ? Color(white: 0.3) : Color(red: 1.0, green: 0.85, blue: 0.4))
                }
            }
        }
    }

    // MARK: - Status label

    @ViewBuilder
    private var statusLabel: some View {
        switch saveStatus {
        case .failure:
            HStack(spacing: 6) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.red)
                Text("SAVE FAILED")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.red)
                    .tracking(2)
            }
        case .saving, .success, nil:
            // Deliberately wordless. A successful capture is signalled by the
            // shutter blink and the haptic tap instead, the way the built in
            // Camera app does it. Failure keeps its label above: silence there
            // would be indistinguishable from success, and someone would walk
            // away believing they had captured something they hadn't.
            //
            // Still rendered as a blank line so the shutter row below never
            // shifts as the status changes.
            Text(" ")
                .font(.system(size: 11, design: .monospaced))
        }
    }

    /// Re-reads the attached camera's true exposure bias range. Called after
    /// initial setup and after every flip, since the front and back cameras
    /// commonly report DIFFERENT ranges from each other.
    private func refreshExposureBiasRange(session: AVCaptureSession?) {
        currentExposureBiasRange(session: session, on: PhotoCameraView.sessionQueue) { range in
            exposureBiasRange = range
            // A range change can leave the current bias outside the new
            // bounds (most concretely right after a flip, where the other
            // camera's range may be narrower) — Slider requires its value stay
            // within `in:`, so this pulls it back in rather than crashing.
            exposureBias = min(max(exposureBias, range.lowerBound), range.upperBound)
        }
    }

    // MARK: - Pro mode
    //
    // Same compact preview card as Save Battery — this only adds a small
    // control strip above the shutter row: exposure compensation and an
    // AE/AF lock, mirroring the video tab's Pro mode controls.

    private var proControlsPanel: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.6))
                Slider(value: Binding(
                    get: { exposureBias },
                    set: { newValue in
                        exposureBias = newValue
                        applyExposureBias(newValue, session: captureSession, on: PhotoCameraView.sessionQueue) { applied in
                            exposureBias = applied
                        }
                    }
                ), in: exposureBiasRange)
                Text(String(format: "%+.1f", exposureBias))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(white: 0.7))
                    .frame(width: 40, alignment: .trailing)
            }

            Button(action: {
                isAutoLocked.toggle()
                setAutoLock(isAutoLocked, session: captureSession, on: PhotoCameraView.sessionQueue)
            }) {
                HStack(spacing: 6) {
                    Image(systemName: isAutoLocked ? "lock.fill" : "lock.open.fill")
                    // See ContentView's identical panel for why .tracking()
                    // sits on the Text rather than the enclosing HStack.
                    Text(isAutoLocked ? "AE / AF LOCKED" : "LOCK AE / AF")
                        .tracking(0.5)
                }
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(isAutoLocked ? .black : Color(white: 0.8))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isAutoLocked ? Color(red: 1.0, green: 0.85, blue: 0.4) : Color(white: 0.15))
                .cornerRadius(6)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.55)))
    }

    // MARK: - Shutter button

    // Shutter button flanked by: flip-camera + dim-screen toggle (left — flip
    // outermost, moon closest to the shutter, moon always available so the
    // user can dim the screen and fire the shutter via the volume button
    // covertly) and the settings (gear) button (right) for the shared Settings screen.
    private var shutterRow: some View {
        ZStack {
            shutterButton
                .reorientIcon(circleIconRotation)

            HStack {
                HStack(spacing: 10) {
                    flipButton
                        .reorientIcon(circleIconRotation)
                    dimButton
                        .reorientIcon(circleIconRotation)
                }
                .padding(.leading, 20)
                Spacer()
                HStack(spacing: 10) {
                    zoomButton
                        .reorientIcon(circleIconRotation)
                    settingsButton
                        .reorientIcon(circleIconRotation)
                }
                .padding(.trailing, 20)
            }
        }
    }

    /// Tap resets to 1x — pinch does the actual zooming, this is the same
    /// "double tap to reset" convention Photos uses, just as a persistent
    /// button rather than a gesture, since the label doubles as a live
    /// readout of the current factor.
    private var zoomButton: some View {
        Button(action: {
            guard let session = captureSession else { return }
            applyZoom(1.0, session: session, on: PhotoCameraView.sessionQueue) { applied in
                zoomFactor = applied
            }
        }) {
            Text(String(format: "%.1f×", zoomFactor))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(isFlatTheme ? previewAccent : Color(white: 0.75))
                .frame(width: 44, height: 44)
                .background(
                    Group {
                        if isFlatTheme {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.black)
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(previewAccent, lineWidth: 2))
                        } else {
                            Circle()
                                .fill(Color(white: 0.14))
                                .overlay(Circle().stroke(Color(white: 0.3), lineWidth: 1))
                                .shadow(color: .black.opacity(0.4), radius: 3, x: 1, y: 2)
                        }
                    }
                )
        }
    }

    @ViewBuilder
    private var flipButton: some View {
        if isFlatTheme {
            Button(action: flipCamera) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.black)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(flipAccent, lineWidth: 2))
                        .frame(width: 44, height: 44)
                    Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(flipAccent)
                }
            }
        } else {
            Button(action: flipCamera) {
                ZStack {
                    Circle()
                        .fill(Color(white: 0.14))
                        .overlay(Circle().stroke(Color(white: 0.3), lineWidth: 1))
                        .frame(width: 44, height: 44)
                        .shadow(color: .black.opacity(0.4), radius: 3, x: 1, y: 2)
                    Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(Color(white: 0.75))
                }
            }
        }
    }

    // App-wide settings (display mode, video/camera quality, low light) —
    // shared with the Video tab via @AppStorage.
    @ViewBuilder
    private var settingsButton: some View {
        if isFlatTheme {
            Button(action: { showAppSettingsSheet = true }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.black)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(settingsAccent, lineWidth: 2))
                        .frame(width: 44, height: 44)
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(settingsAccent)
                }
            }
        } else {
            Button(action: { showAppSettingsSheet = true }) {
                ZStack {
                    Circle()
                        .fill(Color(white: 0.14))
                        .overlay(Circle().stroke(Color(white: 0.3), lineWidth: 1))
                        .frame(width: 44, height: 44)
                        .shadow(color: .black.opacity(0.4), radius: 3, x: 1, y: 2)
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(Color(white: 0.75))
                }
            }
        }
    }

    @ViewBuilder
    private var shutterButton: some View {
        if isFlatTheme {
            simpleShutterButton
        } else {
            ruggedShutterButton
        }
    }

    // Flat Bauhaus/Tactical shutter button: no gradient, no shadow, no
    // knurling — a plain ring and a solid geometric disc, matching the Video
    // tab's style. Tactical adds a faint glow around the ring while capturing.
    private var simpleShutterButton: some View {
        Button(action: capturePhoto) {
            ZStack {
                Circle()
                    .fill(Color.black)
                    .frame(width: btnOuter, height: btnOuter)
                    .overlay(Circle().stroke(isCapturing ? shutterAccent.opacity(0.4) : Color.white, lineWidth: 3))
                    .shadow(color: (appTheme == .tactical && isCapturing) ? shutterAccent : .clear, radius: 10)

                Circle()
                    .fill(isCapturing ? shutterAccent.opacity(0.4) : shutterAccent)
                    .frame(width: btnInner, height: btnInner)

                Image(systemName: "camera.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.black)
            }
            .frame(width: btnFrame, height: btnFrame)
        }
        .disabled(isCapturing || photoOutput == nil)
    }

    private var ruggedShutterButton: some View {
        Button(action: capturePhoto) {
            ZStack {
                // Knurled tick marks — identical treatment to the video record button
                ForEach(0..<36, id: \.self) { i in
                    Capsule()
                        .fill(i % 3 == 0 ? Color(white: 0.55) : Color(white: 0.28))
                        .frame(width: i % 3 == 0 ? 3 : 2,
                               height: i % 3 == 0 ? 10 : 6)
                        .offset(y: -btnTickOffset)
                        .rotationEffect(.degrees(Double(i) * 10))
                }

                // Outer metallic ring
                Circle()
                    .fill(RadialGradient(
                        gradient: Gradient(colors: [Color(white: 0.38), Color(white: 0.14)]),
                        center: .topLeading, startRadius: 5, endRadius: 80
                    ))
                    .frame(width: btnOuter, height: btnOuter)
                    .shadow(color: .black.opacity(0.7), radius: 10, x: 5, y: 5)
                    .overlay(Circle().stroke(Color(white: 0.5), lineWidth: 1))

                // Button face — dims while capturing
                Circle()
                    .fill(RadialGradient(
                        gradient: Gradient(colors: isCapturing
                            ? [Color(white: 0.6), Color(white: 0.35)]
                            : [Color(white: 0.92), Color(white: 0.65)]
                        ),
                        center: .topLeading, startRadius: 3, endRadius: 55
                    ))
                    .frame(width: btnInner, height: btnInner)
                    .shadow(color: .black.opacity(0.4), radius: 4, x: 2, y: 2)

                // Camera icon
                Image(systemName: "camera.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(isCapturing ? Color(white: 0.5) : Color(white: 0.2))
            }
            .frame(width: btnFrame, height: btnFrame)
        }
        .disabled(isCapturing || photoOutput == nil)
    }

    // MARK: - Session Setup

    private func setupCaptureSession() {
        PhotoCameraView.sessionQueue.async {
            let session = AVCaptureSession()
            session.beginConfiguration()
            session.sessionPreset = .photo

            guard
                let device = bestCaptureDevice(position: .back),
                let input = try? AVCaptureDeviceInput(device: device),
                session.canAddInput(input)
            else {
                print("PhotoCameraView: failed to configure camera input")
                return
            }
            session.addInput(input)

            let output = AVCapturePhotoOutput()
            guard session.canAddOutput(output) else {
                print("PhotoCameraView: failed to add photo output")
                return
            }
            session.addOutput(output)
            session.commitConfiguration()
            session.startRunning()

            DispatchQueue.main.async {
                self.photoOutput = output
                self.captureSession = session
                // Only now are photoOutput/captureSession set, which
                // applyPhotoDimensions reads — hence here rather than beside
                // startRunning above.
                self.applyPhotoDimensions(overrideSession: session)
                self.refreshExposureBiasRange(session: session)
            }
        }
    }

    /// The still image size to request from `device` for a given tier: its true
    /// maximum for Max, its smallest supported size otherwise.
    ///
    /// Always drawn from the device's CURRENT activeFormat, because those are
    /// the only values AVFoundation will accept for maxPhotoDimensions — any
    /// other value, including zero, throws rather than being rejected politely.
    @available(iOS 16.0, *)
    private static func photoDimensions(for device: AVCaptureDevice,
                                        quality: PhotoQuality) -> CMVideoDimensions? {
        let supported = device.activeFormat.supportedMaxPhotoDimensions
        let smallerByArea: (CMVideoDimensions, CMVideoDimensions) -> Bool = {
            Int64($0.width) * Int64($0.height) < Int64($1.width) * Int64($1.height)
        }
        return quality == .max
            ? supported.max(by: smallerByArea)
            : supported.min(by: smallerByArea)
    }

    /// Points the output's resolution ceiling at what the currently attached
    /// camera supports for the selected tier.
    ///
    /// Call this only when a session reconfiguration is safe — after setup,
    /// on a quality change, or after a camera flip — never immediately before
    /// a capture, since committing a change to a running session drops the
    /// video connection for a moment and any capture racing that will raise.
    ///
    /// `overrideSession` covers setupCaptureSession's own call, where the
    /// session it just built has not been assigned to the @State property yet.
    private func applyPhotoDimensions(overrideSession: AVCaptureSession? = nil) {
        guard #available(iOS 16.0, *) else { return }
        guard let session = overrideSession ?? captureSession,
              let output = photoOutput else { return }
        let selected = quality
        PhotoCameraView.sessionQueue.async {
            // Read the device INSIDE the queue: a flip may still be in flight,
            // and a value drawn from a camera that is no longer attached is
            // exactly what AVFoundation rejects.
            guard let device = session.inputs
                .compactMap({ $0 as? AVCaptureDeviceInput })
                .first(where: { $0.device.hasMediaType(.video) })?.device,
                  let dims = PhotoCameraView.photoDimensions(for: device, quality: selected)
            else { return }

            // Field by field: CMVideoDimensions is a plain C struct with no
            // Equatable conformance. Skipping a no-op write matters beyond
            // tidiness — committing an unchanged value still cycles the
            // session's connections for nothing.
            let current = output.maxPhotoDimensions
            guard current.width != dims.width || current.height != dims.height else { return }

            session.beginConfiguration()
            output.maxPhotoDimensions = dims
            session.commitConfiguration()
        }
    }

    // MARK: - Capture

    /// Blinks the viewfinder to black and fades it back, the built in Camera
    /// app's acknowledgement of a shutter.
    ///
    /// The blink is set without animation and cleared with one, so it snaps to
    /// black instantly and eases back out. Wrapping both halves in a single
    /// animation would cross fade INTO black too, which reads as a slow dip
    /// rather than a shutter.
    private func flashShutter() {
        shutterFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeOut(duration: 0.2)) { shutterFlash = false }
        }
    }

    private func capturePhoto() {
        // Still guards against a genuine double-fire of ONE tap — the volume
        // button calls capturePhoto() directly, bypassing the shutter
        // button's own .disabled(isCapturing), so this is the only thing
        // stopping that path from double-triggering. Its window is now just
        // "until this specific shot's shutter fires" (well under a second),
        // not the whole save pipeline, so a second, genuinely separate tap
        // shortly after is no longer blocked by it — see onShutterFired below.
        guard !isCapturing, let output = photoOutput else { return }
        isCapturing = true
        saveStatus  = .saving

        // Fired on press rather than when the file finishes writing: this is
        // acknowledgement that the shutter was taken, and it has to feel
        // immediate. The save result is reported separately, and only when it
        // fails.
        flashShutter()
        // A soft tick in place of the system shutter, which is suppressed in
        // the delegate. Follows the silent switch, so a muted phone still
        // captures silently.
        ShutterTick.play()
        // Also tapped, so the confirmation still lands when the phone is on
        // silent. Does nothing on hardware without a Taptic Engine, which is a
        // no-op rather than an error.
        hapticGenerator.impactOccurred()
        // Re-arm for the next shot; a generator goes back to idle after firing.
        hapticGenerator.prepare()

        // Snapshotted now rather than read again once the shutter actually
        // fires: quality is a shared @AppStorage value, and with more than
        // one capture able to be in flight at once, a setting change made
        // between this tap and its shutter firing must not retroactively
        // change what THIS shot was taken with.
        let capturedQuality = quality

        // Read on the main thread (UIKit call); AVFoundation defaults new
        // connections to portrait, so without this landscape photos come out
        // sideways.
        let captureOrientation = currentCaptureOrientation()

        // Drop volume to 0 BEFORE the shutter fires — this silences the system
        // shutter sound without any visible or audible indication to bystanders.
        // A 60 ms gap gives the audio stack time to apply the new level.
        volumeObserver.silenceForCapture()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            PhotoCameraView.sessionQueue.async {
                // Deliberately does NOT reconfigure the session here.
                //
                // This used to wrap a maxPhotoDimensions change in
                // beginConfiguration/commitConfiguration and then call
                // capturePhoto immediately afterwards. Committing a change to a
                // RUNNING session tears the video connection down and rebuilds
                // it, so the capture landed while there was no active
                // connection — which AVFoundation raises on rather than
                // failing quietly.
                //
                // It only ever showed up right after a quality change because
                // writing the SAME value back is a no-op that reconfigures
                // nothing; only a genuinely different value forces the
                // teardown. Relaunching appeared to fix it because a fresh
                // output already defaults to what the non-Max tiers ask for, so
                // that first capture changed nothing either.
                //
                // The output is now configured by applyPhotoDimensions() at the
                // moments a reconfiguration is actually safe — after setup,
                // when the quality setting changes, and after a camera flip —
                // leaving this path to only READ what is already in place.
                //
                // JPEG is requested from the sensor to avoid HEIF/HEVC format
                // issues; quality differences other than resolution are applied
                // in the delegate via post-processing.
                let settings = AVCapturePhotoSettings(
                    format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
                if #available(iOS 16.0, *) {
                    let current = output.maxPhotoDimensions
                    if current.width > 0 && current.height > 0 {
                        settings.maxPhotoDimensions = current
                    }
                }

                if let connection = output.connection(with: .video) {
                    connection.videoOrientation = captureOrientation
                }

                self.captureDelegate.beginCapture(
                    settings: settings,
                    quality: capturedQuality,
                    onShutterFired: {
                        // The shutter for THIS shot has fired — the button can
                        // pop back up now rather than waiting for the save
                        // pipeline below to finish, which is the whole point.
                        self.isCapturing = false
                    },
                    onFinish: { success in
                        // Restores whatever this shot's own silenceForCapture
                        // call dropped. VolumeButtonObserver's suppression is
                        // reference counted specifically so overlapping
                        // silence/restore pairs from concurrent captures don't
                        // clear each other's window early.
                        self.volumeObserver.restoreAfterCapture()
                        // Last writer wins if more than one capture is
                        // in flight — acceptable here since only .failure
                        // renders anything to begin with.
                        self.saveStatus = success ? .success : .failure
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            self.saveStatus = nil
                        }
                    }
                )
                output.capturePhoto(with: settings, delegate: self.captureDelegate)
            }
        }
    }

    // MARK: - Camera Flip

    private func flipCamera() {
        guard let session = captureSession else { return }
        isUsingFront.toggle()
        // The device being attached below always starts at 1x regardless of
        // what the outgoing camera was zoomed to, so the readout follows suit
        // immediately rather than showing a stale value from the old camera.
        zoomFactor = 1.0
        exposureBias = 0
        isAutoLocked = false
        let position: AVCaptureDevice.Position = isUsingFront ? .front : .back

        PhotoCameraView.sessionQueue.async {
            session.beginConfiguration()
            let previousInputs = session.inputs.compactMap { $0 as? AVCaptureDeviceInput }
            for input in previousInputs { session.removeInput(input) }

            // Deliberately does NOT touch photoOutput.maxPhotoDimensions here.
            // At this point every input is gone, so there is no video source
            // device and no activeFormat to validate a new value against —
            // AVFoundation throws on ANY value in that state, including zero.
            // capturePhoto owns that property instead, setting it fresh from
            // whichever device is attached at the moment of capture.
            guard
                let device = bestCaptureDevice(position: position),
                let newInput = try? AVCaptureDeviceInput(device: device),
                session.canAddInput(newInput)
            else {
                // Put the previous camera back rather than committing a
                // session with no input at all, which renders as a
                // permanently black preview. This tab pins sessionPreset to
                // .photo, which both cameras satisfy, so canAddInput isn't
                // expected to fail here — but the video tab hit exactly this
                // failure mode and a dead preview is far worse than a flip
                // that simply doesn't happen.
                for input in previousInputs where session.canAddInput(input) {
                    session.addInput(input)
                }
                session.commitConfiguration()
                DispatchQueue.main.async { self.isUsingFront.toggle() }
                return
            }
            session.addInput(newInput)
            session.commitConfiguration()
            // Otherwise the newly selected camera inherits the previous one's
            // tap-to-focus point, which rarely makes sense for a different lens.
            resetFocusToContinuous(session: session, on: PhotoCameraView.sessionQueue)
            // The incoming camera's supported sizes are its own, so the
            // ceiling has to be recomputed against it rather than inherited.
            DispatchQueue.main.async {
                self.applyPhotoDimensions()
                // The front and back cameras commonly report DIFFERENT
                // exposure bias ranges, so this can't just be reset to a
                // fixed default — it has to be re-read from whichever camera
                // is now attached.
                self.refreshExposureBiasRange(session: session)
            }
        }
    }

    // MARK: - Screen Dim

    private func toggleDim() { isScreenDimmed ? wakeScreen() : dimScreen() }

    private func dimScreen() {
        savedBrightness = UIScreen.main.brightness
        UIScreen.main.brightness = 0.01
        isScreenDimmed = true
        NotificationCenter.default.post(name: .screenDidDim, object: nil)
    }

    private func wakeScreen() {
        UIScreen.main.brightness = savedBrightness
        isScreenDimmed = false
        NotificationCenter.default.post(name: .screenDidWake, object: nil)
    }

    private func restoreBrightness() {
        guard isScreenDimmed else { return }
        wakeScreen()
    }
}
