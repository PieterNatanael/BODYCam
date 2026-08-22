import SwiftUI
import AVFoundation

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

// MARK: - Photo Capture Delegate

final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, ObservableObject {
    /// Set before each capture so the delegate knows how to process the image.
    var quality: PhotoQuality = .high
    var onFinish: ((Bool) -> Void)?

    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil,
              let rawData = photo.fileDataRepresentation(),
              let rawImage = UIImage(data: rawData) else {
            DispatchQueue.main.async { self.onFinish?(false) }
            return
        }

        // --- Post-process on the background thread AVFoundation already gave us ---

        // 1. Scale down if needed (LOW = 50 % linear → 25 % of pixels)
        let scale = quality.spatialScale
        let processed: UIImage
        if scale < 1.0 {
            let targetSize = CGSize(width:  rawImage.size.width  * scale,
                                    height: rawImage.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: targetSize)
            processed = renderer.image { _ in
                rawImage.draw(in: CGRect(origin: .zero, size: targetSize))
            }
        } else {
            processed = rawImage
        }

        // 2. Re-encode as JPEG with the tier's compression factor
        guard let jpeg = processed.jpegData(compressionQuality: quality.jpegCompression) else {
            DispatchQueue.main.async { self.onFinish?(false) }
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
            DispatchQueue.main.async { self.onFinish?(true) }
        } catch {
            DispatchQueue.main.async { self.onFinish?(false) }
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
    private static let sessionQueue = DispatchQueue(
        label: "com.bodycam.photo.session", qos: .userInitiated)

    // MARK: - UI State

    @AppStorage("SelectedPhotoQuality") private var quality: PhotoQuality = .high
    @State private var isUsingFront     = false
    @State private var isCapturing      = false
    @State private var saveStatus: SaveStatus?
    @State private var isScreenDimmed   = false
    @State private var savedBrightness: CGFloat = UIScreen.main.brightness
    @State private var showAppSettingsSheet = false
    @AppStorage("CameraDisplayMode") private var displayModeRaw: String = CameraDisplayMode.normal.rawValue
    private var displayMode: CameraDisplayMode { CameraDisplayMode(rawValue: displayModeRaw) ?? .saveBattery }
    @AppStorage("AppTheme") private var appThemeRaw: String = AppTheme.simple.rawValue
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
    private var previewCardWidth: CGFloat { UIScreen.main.bounds.width - 48 }
    private var previewCardHeight: CGFloat {
        let natural: CGFloat = previewCardWidth * 4 / 3
        let reserved: CGFloat = isCompact ? 260 : 300
        return min(natural, UIScreen.main.bounds.height - reserved)
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
        }
        .onDisappear {
            restoreBrightness()
            volumeObserver.stop()
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
            // Release the camera so the Video tab can reclaim it
            let session = captureSession
            PhotoCameraView.sessionQueue.async { session?.stopRunning() }
        }
        // RootView → PhotoCameraView: restore brightness when user taps overlay
        .onReceive(NotificationCenter.default.publisher(for: .userRequestedWake)) { _ in
            wakeScreen()
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
                               center: .center, startRadius: previewCardWidth / 2, endRadius: screenGlowRadius)
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
            Spacer()
            if !subscriptionManager.isUnlocked {
                goProBadge
                    .padding(.trailing)
            }
        }
        .padding(.vertical, 8)
        .frame(height: isCompact ? 34 : 42)
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
            let topInset = geo.safeAreaInsets.top
            let bottomInset = geo.safeAreaInsets.bottom
            let w: CGFloat = isNormal
                ? geo.size.width + geo.safeAreaInsets.leading + geo.safeAreaInsets.trailing
                : previewCardWidth
            let h: CGFloat = isNormal ? geo.size.height + topInset + bottomInset : previewCardHeight
            let verticalOffset: CGFloat = isNormal ? (bottomInset - topInset) / 2 : 0
            let radius: CGFloat = isNormal ? 0 : previewCornerRadius
            let borderColor: Color = isNormal ? Color.clear : previewBorderColor
            let borderWidth: CGFloat = isNormal ? 0 : previewBorderWidth
            let placeholderFill: Color = (isFlatTheme || isNormal) ? Color.black : Color(white: 0.05)
            let accentColor: Color = isFlatTheme ? previewAccent : Color(white: 0.2)
            let decoration: PreviewFrameDecoration = isNormal ? .border : previewDecoration

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
                    CameraPreviewView(session: session,
                                      isPreviewActive: !isScreenDimmed) { devicePoint in
                        applyTapToFocus(session: captureSession,
                                        devicePoint: devicePoint,
                                        on: PhotoCameraView.sessionQueue)
                    }
                    .frame(width: w, height: h)
                    .cornerRadius(radius)
                    .overlay(
                        previewBorderOverlay(radius: radius, color: borderColor,
                                              width: borderWidth, decoration: decoration)
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
        case .saving:
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.75)
                Text("SAVING…")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(white: 0.5))
                    .tracking(2)
            }
        case .success:
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundColor(.green)
                Text("SAVED TO GALLERY")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.green)
                    .tracking(2)
            }
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
        case nil:
            // Reserve height so layout doesn't jump
            Text(" ")
                .font(.system(size: 11, design: .monospaced))
        }
    }

    // MARK: - Shutter button

    // Shutter button flanked by: flip-camera + dim-screen toggle (left — flip
    // outermost, moon closest to the shutter, moon always available so the
    // user can dim the screen and fire the shutter via the volume button
    // covertly) and the settings (gear) button (right) for the shared Settings screen.
    private var shutterRow: some View {
        ZStack {
            shutterButton

            HStack {
                HStack(spacing: 10) {
                    flipButton
                    dimButton
                }
                .padding(.leading, 20)
                Spacer()
                settingsButton
                    .padding(.trailing, 20)
            }
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
                let device = AVCaptureDevice.default(
                    .builtInWideAngleCamera, for: .video, position: .back),
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

    // MARK: - Capture

    private func capturePhoto() {
        guard !isCapturing, let output = photoOutput else { return }
        isCapturing = true
        saveStatus  = .saving

        // Always request JPEG from the sensor — avoids HEIF/HEVC format issues.
        // Quality differences other than resolution are applied in the
        // delegate via post-processing.
        let settings = AVCapturePhotoSettings(
            format: [AVVideoCodecKey: AVVideoCodecType.jpeg])

        captureDelegate.quality = quality
        captureDelegate.onFinish = { success in
            // Restore volume now that the shutter has fired
            self.volumeObserver.restoreAfterCapture()
            self.saveStatus  = success ? .success : .failure
            self.isCapturing = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.saveStatus = nil
            }
        }

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
                // The single place this property is ever written. Computed fresh
                // from whichever device is attached RIGHT NOW, rather than
                // cached at setup, on a settings change, or on a camera flip:
                // the device can change out from under any cached value, and a
                // maxPhotoDimensions that doesn't match the current active
                // format's supportedMaxPhotoDimensions throws inside
                // AVFoundation rather than failing gracefully. Applying it in
                // the same breath as the capture call leaves no such window,
                // and covers every tier so a value set for Max on one camera
                // can't linger into a later shot on another.
                if #available(iOS 16.0, *),
                   let session = self.captureSession,
                   let device = session.inputs
                       .compactMap({ $0 as? AVCaptureDeviceInput })
                       .first(where: { $0.device.hasMediaType(.video) })?.device,
                   let dims = PhotoCameraView.photoDimensions(for: device, quality: self.quality) {
                    session.beginConfiguration()
                    output.maxPhotoDimensions = dims
                    session.commitConfiguration()
                    settings.maxPhotoDimensions = dims
                }

                if let connection = output.connection(with: .video) {
                    connection.videoOrientation = captureOrientation
                }
                output.capturePhoto(with: settings, delegate: self.captureDelegate)
            }
        }
    }

    // MARK: - Camera Flip

    private func flipCamera() {
        guard let session = captureSession else { return }
        isUsingFront.toggle()
        let position: AVCaptureDevice.Position = isUsingFront ? .front : .back

        PhotoCameraView.sessionQueue.async {
            session.beginConfiguration()
            for input in session.inputs { session.removeInput(input) }

            // Deliberately does NOT touch photoOutput.maxPhotoDimensions here.
            // At this point every input is gone, so there is no video source
            // device and no activeFormat to validate a new value against —
            // AVFoundation throws on ANY value in that state, including zero.
            // capturePhoto owns that property instead, setting it fresh from
            // whichever device is attached at the moment of capture.
            guard
                let device = AVCaptureDevice.default(
                    .builtInWideAngleCamera, for: .video, position: position),
                let newInput = try? AVCaptureDeviceInput(device: device),
                session.canAddInput(newInput)
            else {
                session.commitConfiguration()
                return
            }
            session.addInput(newInput)
            session.commitConfiguration()
            // Otherwise the newly selected camera inherits the previous one's
            // tap-to-focus point, which rarely makes sense for a different lens.
            resetFocusToContinuous(session: session, on: PhotoCameraView.sessionQueue)
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
