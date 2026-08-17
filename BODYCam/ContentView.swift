import SwiftUI
import AVFoundation

struct ContentView: View {

    // MARK: - State

    @State private var isRecording = false
    @State private var captureSession: AVCaptureSession?
    @State private var videoOutput: AVCaptureMovieFileOutput?
    @State private var videoURL: URL?
    @AppStorage("SelectedVideoQuality") private var selectedQuality: VideoQuality = .low
    @AppStorage("IsLowLight") private var isLowLight: Bool = false
    @State private var isUsingFront  = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showAlert = false
    @State private var isScreenDimmed = false
    @State private var savedBrightness: CGFloat = UIScreen.main.brightness
    @State private var showAppSettingsSheet = false
    /// Whether this tab is currently on screen. Camera setup is asynchronous
    /// and slow (1 to 3 seconds), so the user can easily leave before it
    /// finishes — see setupCaptureSession's completion block.
    @State private var isTabVisible = false
    @AppStorage("CameraDisplayMode") private var displayModeRaw: String = CameraDisplayMode.normal.rawValue
    private var displayMode: CameraDisplayMode { CameraDisplayMode(rawValue: displayModeRaw) ?? .saveBattery }
    @AppStorage("AppTheme") private var appThemeRaw: String = AppTheme.simple.rawValue
    private var appTheme: AppTheme { AppTheme(rawValue: appThemeRaw) ?? .normal }
    // Simple and Tactical share the same flat/no-gradient/sharp-corner "bones";
    // only their accent colors (and the preview's corner-bracket treatment) differ.
    private var isFlatTheme: Bool { appTheme != .normal }
    private var useCornerBrackets: Bool { appTheme == .tactical }

    // MARK: - Theme accent palette
    private let simpleRed     = Color(red: 0.85, green: 0.15, blue: 0.1)
    private let simpleYellow  = Color(red: 0.95, green: 0.78, blue: 0.1)
    private let simpleBlue    = Color(red: 0.15, green: 0.4,  blue: 0.85)
    private let tacticalGreen = Color(red: 0.25, green: 0.95, blue: 0.4)

    private var flipAccent: Color     { appTheme == .tactical ? tacticalGreen : simpleBlue }
    private var dimAccent: Color      { appTheme == .tactical ? tacticalGreen : simpleYellow }
    private var settingsAccent: Color { appTheme == .tactical ? tacticalGreen : simpleRed }
    private var recordAccent: Color   { appTheme == .tactical ? tacticalGreen : simpleRed }
    private var previewAccent: Color  { appTheme == .tactical ? tacticalGreen : simpleRed }

    // @StateObject keeps the same delegate instance alive across view re-renders.
    // A plain `let` in a SwiftUI struct is recreated on every render, which would
    // break the delegate → file-move handshake.
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @State private var showPaywall = false

    @StateObject private var videoCaptureDelegate = VideoCaptureDelegate()
    @StateObject private var volumeObserver = VolumeButtonObserver()

    // Apple requirement: ALL AVCaptureSession operations MUST run on a dedicated
    // serial queue — NOT main, NOT DispatchQueue.global() (which is concurrent).
    // Using concurrent threads causes silent audio drops and race conditions.
    private static let sessionQueue = DispatchQueue(label: "com.bodycam.session", qos: .userInitiated)

    // MARK: - Adaptive layout
    // iPhone SE / small screens: height < 700pt
    private var isCompact: Bool { UIScreen.main.bounds.height < 700 }
    private var btnFrame: CGFloat       { isCompact ? 100 : 120 }
    private var btnOuter: CGFloat       { isCompact ? 74  : 90  }
    private var btnInner: CGFloat       { isCompact ? 56  : 70  }
    private var btnTickOffset: CGFloat  { isCompact ? 44  : 54  }
    private var bottomPad: CGFloat      { isCompact ? 12  : 36  }

    // Fixed size (not "fit remaining space") so the preview card renders at the
    // exact same size on this tab and the Camera tab, regardless of how much
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

    // Simple/Tactical: sharp corners + a bold flat accent border (or corner
    // brackets for Tactical), "frame as object" rather than the Normal theme's
    // subtle rounded card-with-depth look.
    private var previewCornerRadius: CGFloat { isFlatTheme ? 0 : 10 }
    private var previewBorderColor: Color { isFlatTheme ? previewAccent : Color(white: 0.3) }
    private var previewBorderWidth: CGFloat { appTheme == .tactical ? 2 : (appTheme == .simple ? 3 : 1) }

    // Tactical gets a viewfinder-style corner-bracket reticle instead of a
    // plain stroked rectangle around the preview frame.
    @ViewBuilder
    private func previewBorderOverlay(radius: CGFloat, color: Color, width: CGFloat, useBrackets: Bool) -> some View {
        if useBrackets {
            CornerBrackets(length: 22)
                .stroke(color, lineWidth: width)
        } else {
            RoundedRectangle(cornerRadius: radius)
                .stroke(color, lineWidth: width)
        }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            background

            sharedPreviewLayer

            // Top chrome differs by mode, but the record row (record button,
            // flip/dim/settings) is a single shared view below — previously each
            // mode had its own copy, and small layout differences between them
            // caused the record row to shift and clip behind the tab bar in
            // Normal mode. Sharing it guarantees an identical position always.
            VStack(spacing: 0) {
                topChrome
                Spacer(minLength: 0)
                recordRow
                    .padding(.bottom, bottomPad)
            }
        }
        .onAppear {
            isTabVisible = true
            // Needed so UIDevice.current.orientation is actually kept up to
            // date — startRecording() reads it to set the recording's
            // orientation so landscape footage comes out right-side-up.
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            if let session = captureSession {
                // Returning from another tab — camera was stopped; restart it
                ContentView.sessionQueue.async {
                    if !session.isRunning { session.startRunning() }
                }
            } else {
                setupCaptureSession()
            }
            volumeObserver.start {
                if self.isRecording { self.stopRecording() }
                else { self.startRecording() }
            }
        }
        .onDisappear {
            isTabVisible = false
            stopRecording()
            volumeObserver.stop()
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
            // Stop the session so the Camera tab (or any other consumer)
            // can claim the hardware. iOS cannot run two sessions at once.
            let session = captureSession
            ContentView.sessionQueue.async { session?.stopRunning() }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            stopRecording()
        }
        .onReceive(NotificationCenter.default.publisher(for: .recordingStoppedWithError)) { notification in
            handleRecordingError(notification.userInfo?["error"] as? Error)
        }
        // RootView posts this when the user taps the screen-off overlay.
        // Using a separate name from .screenDidWake so there is no notification loop:
        // ContentView → .screenDidWake → RootView (hide overlay)
        // RootView tap → .userRequestedWake → ContentView (restore brightness)
        .onReceive(NotificationCenter.default.publisher(for: .userRequestedWake)) { _ in
            wakeScreen()
        }
        // Quality / low-light now live in the shared Settings screen — apply
        // hardware changes here whenever either @AppStorage value changes,
        // regardless of which tab's Settings sheet made the change.
        .onChange(of: selectedQuality) { newValue in
            ContentView.sessionQueue.async {
                captureSession?.beginConfiguration()
                captureSession?.sessionPreset = newValue.preset
                captureSession?.commitConfiguration()
            }
        }
        .onChange(of: isLowLight) { newValue in
            applyLowLight(newValue)
        }
        .alert(isPresented: $showAlert) {
            Alert(
                title: Text(alertTitle),
                message: Text(alertMessage),
                dismissButton: .default(Text("OK"))
            )
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView().environmentObject(subscriptionManager)
        }
        .sheet(isPresented: $showAppSettingsSheet) {
            SettingsView()
        }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var background: some View {
        if isFlatTheme {
            // Bauhaus / Tactical: flat, no texture, no gradient.
            Color.black.ignoresSafeArea()
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

            // Go Pro button — hidden once subscribed
            if !subscriptionManager.isUnlocked {
                goProBadge
                    .padding(.trailing)
            }
        }
        .padding(.vertical, 8)
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
    @ViewBuilder
    private var sharedPreviewLayer: some View {
        // GeometryReader here measures the actual safe content rectangle (the
        // same area the tab bar already keeps clear). The outer container below
        // is pinned to exactly that size — this is what keeps the record row
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
            let showBrackets = useCornerBrackets && !isNormal

            ZStack {
                if let session = captureSession {
                    // Tapping focuses (and re-meters exposure) rather than
                    // toggling the preview. Battery saving is the dim-screen
                    // button's job — it kills the backlight, which dwarfs the
                    // preview layer's own draw cost.
                    CameraPreviewView(session: session) { devicePoint in
                        applyTapToFocus(session: captureSession,
                                        devicePoint: devicePoint,
                                        on: ContentView.sessionQueue)
                    }
                    .frame(width: w, height: h)
                    .cornerRadius(radius)
                    .overlay(
                        previewBorderOverlay(radius: radius, color: borderColor,
                                              width: borderWidth, useBrackets: showBrackets)
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
                                                      width: borderWidth, useBrackets: showBrackets)
                            )
                        VStack(spacing: 10) {
                            Image(systemName: "video.fill")
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

    // Record button flanked by: flip-camera + dim-screen toggle (left — flip
    // outermost, moon closest to the record button, only while recording) and
    // the settings (gear) button (right) that opens the shared Settings screen.
    private var recordRow: some View {
        ZStack {
            Button(action: { isRecording ? stopRecording() : startRecording() }) {
                recordButtonView
            }

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
                        .foregroundColor(isRecording ? flipAccent.opacity(0.3) : flipAccent)
                }
            }
            .disabled(isRecording)
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
                        .foregroundColor(isRecording ? Color(white: 0.3) : Color(white: 0.75))
                }
            }
            .disabled(isRecording)
        }
    }

    // App-wide settings (display mode, video/camera quality, low light) —
    // shared with the Camera tab via @AppStorage.
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
                        .foregroundColor(isRecording ? settingsAccent.opacity(0.3) : settingsAccent)
                }
            }
            .disabled(isRecording)
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
                        .foregroundColor(isRecording ? Color(white: 0.3) : Color(white: 0.75))
                }
            }
            .disabled(isRecording)
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

    @ViewBuilder
    private var recordButtonView: some View {
        if isFlatTheme {
            simpleRecordButton
        } else {
            ruggedRecordButton
        }
    }

    // Flat Bauhaus/Tactical record button: no gradient, no shadow, no
    // knurling — a plain ring and a solid geometric shape signalling state.
    // Tactical adds a faint glow around the ring while recording.
    private var simpleRecordButton: some View {
        ZStack {
            Circle()
                .fill(Color.black)
                .frame(width: btnOuter, height: btnOuter)
                .overlay(Circle().stroke(isRecording ? recordAccent : Color.white, lineWidth: 3))
                .shadow(color: (appTheme == .tactical && isRecording) ? recordAccent : .clear, radius: 10)

            if isRecording {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white)
                    .frame(width: 22, height: 22)
            } else {
                Circle()
                    .fill(recordAccent)
                    .frame(width: btnInner, height: btnInner)
            }
        }
        .frame(width: btnFrame, height: btnFrame)
    }

    private var ruggedRecordButton: some View {
        ZStack {
            // Knurled tick marks
            ForEach(0..<36, id: \.self) { i in
                Capsule()
                    .fill(i % 3 == 0 ? Color(white: 0.55) : Color(white: 0.28))
                    .frame(width: i % 3 == 0 ? 3 : 2, height: i % 3 == 0 ? 10 : 6)
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

            // Button face
            Circle()
                .fill(RadialGradient(
                    gradient: Gradient(colors: isRecording
                        ? [Color(red: 0.85, green: 0.12, blue: 0.12), Color(red: 0.45, green: 0.04, blue: 0.04)]
                        : [Color(white: 0.92), Color(white: 0.65)]
                    ),
                    center: .topLeading, startRadius: 3, endRadius: 55
                ))
                .frame(width: btnInner, height: btnInner)
                .shadow(color: .black.opacity(0.4), radius: 4, x: 2, y: 2)

            // Center icon: red dot = ready, white square = stop
            if isRecording {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(white: 0.9))
                    .frame(width: 20, height: 20)
            } else {
                Circle()
                    .fill(Color(red: 0.85, green: 0.1, blue: 0.1))
                    .frame(width: 18, height: 18)
            }
        }
        .frame(width: btnFrame, height: btnFrame)
    }

    // MARK: - Settings

    private func flipCamera() {
        guard let session = captureSession, !isRecording else { return }
        isUsingFront.toggle()
        let position: AVCaptureDevice.Position = isUsingFront ? .front : .back

        ContentView.sessionQueue.async {
            session.beginConfiguration()
            // Remove only video inputs — keep the audio input
            let videoInputs = session.inputs.compactMap { $0 as? AVCaptureDeviceInput }
                .filter { $0.device.hasMediaType(.video) }
            for input in videoInputs { session.removeInput(input) }

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
            resetFocusToContinuous(session: session, on: ContentView.sessionQueue)
        }
    }

    private func applyLowLight(_ enabled: Bool) {
        guard let device = AVCaptureDevice.default(for: .video) else { return }
        ContentView.sessionQueue.async {
            do {
                try device.lockForConfiguration()
                if enabled {
                    // 30fps = longer shutter = more light per frame
                    device.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: 30)
                    device.activeVideoMaxFrameDuration = CMTimeMake(value: 1, timescale: 30)
                    // Hardware low light boost (supported on most modern iPhones)
                    if device.isLowLightBoostSupported {
                        device.automaticallyEnablesLowLightBoostWhenAvailable = true
                    }
                } else {
                    // Reset to automatic frame rate
                    device.activeVideoMinFrameDuration = CMTime.invalid
                    device.activeVideoMaxFrameDuration = CMTime.invalid
                    if device.isLowLightBoostSupported {
                        device.automaticallyEnablesLowLightBoostWhenAvailable = false
                    }
                }
                device.unlockForConfiguration()
            } catch {
                print("Low light config error: \(error)")
            }
        }
    }

    // MARK: - Session Setup

    private func setupCaptureSession() {
        ContentView.sessionQueue.async {

            // Fix: explicitly configure AVAudioSession BEFORE starting the
            // capture session. Without this iOS reclaims the audio session
            // after ~10 seconds and audio drops out.
            let audioSession = AVAudioSession.sharedInstance()
            do {
                try audioSession.setCategory(.playAndRecord,
                                            mode: .videoRecording,
                                            options: [.defaultToSpeaker, .allowBluetooth])
                try audioSession.setActive(true)
            } catch {
                print("Audio session setup error: \(error)")
            }

            let session = AVCaptureSession()

            guard let videoDevice = AVCaptureDevice.default(for: .video),
                  let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
                  session.canAddInput(videoInput) else {
                print("Failed to configure video input.")
                return
            }
            session.addInput(videoInput)

            guard let audioDevice = AVCaptureDevice.default(for: .audio),
                  let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
                  session.canAddInput(audioInput) else {
                print("Failed to configure audio input.")
                return
            }
            session.addInput(audioInput)

            let output = AVCaptureMovieFileOutput()
            guard session.canAddOutput(output) else {
                print("Failed to add video output.")
                return
            }
            session.addOutput(output)

            // Video: H.264
            if let videoConnection = output.connections.first(where: {
                $0.inputPorts.contains(where: { $0.mediaType == .video })
            }) {
                output.setOutputSettings(
                    [AVVideoCodecKey: AVVideoCodecType.h264],
                    for: videoConnection
                )
            }

            // Audio: low quality AAC — mono, 22050 Hz, 32kbps
            // Saves battery + storage, perfectly fine for voice/ambient
            if let audioConnection = output.connections.first(where: {
                $0.inputPorts.contains(where: { $0.mediaType == .audio })
            }) {
                output.setOutputSettings([
                    AVFormatIDKey:            kAudioFormatMPEG4AAC,
                    AVSampleRateKey:          22050,
                    AVNumberOfChannelsKey:    1,
                    AVEncoderBitRateKey:      32000
                ], for: audioConnection)
            }

            session.beginConfiguration()
            session.sessionPreset = self.selectedQuality.preset
            session.commitConfiguration()

            session.startRunning()

            // Apply saved low light setting after session starts
            self.applyLowLight(self.isLowLight)

            DispatchQueue.main.async {
                self.videoOutput = output
                self.captureSession = session

                // The user can leave this tab while the camera is still
                // starting up — most notably when a tapped alarm/reminder
                // routes straight to the Gallery. onDisappear already ran, but
                // it captured `captureSession` while it was still nil, so its
                // `session?.stopRunning()` silently no-opped and left this
                // session running. That matters beyond wasted battery: this
                // session carries an audio input, and a running capture
                // session with a mic interrupts other audio, which is what
                // was pausing a playing video a few seconds in.
                if !self.isTabVisible {
                    ContentView.sessionQueue.async { session.stopRunning() }
                }
            }
        }
    }

    // MARK: - Recording

    private func startRecording() {
        guard let videoOutput else { return }

        // Check available storage before starting
        let freeMB = availableStorageMB()
        guard freeMB > 50 else {
            alertTitle = "Not Enough Storage"
            alertMessage = freeMB <= 0
                ? "Unable to determine available storage. Free up space and try again."
                : "Only \(freeMB) MB remaining. Free up storage space before recording."
            showAlert = true
            return
        }

        // Record to a TEMP file. The delegate moves it to Documents only after
        // finalization is confirmed. This prevents GalleryView from seeing a
        // partial 0-second file while AVFoundation is still writing.
        let timestamp = Date().timeIntervalSince1970
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("bodycam_tmp_\(timestamp).mov")
        let finalURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("video_\(timestamp).mov")

        isRecording = true
        videoURL = finalURL
        UIApplication.shared.isIdleTimerDisabled = true

        // Capture the delegate directly so the closure doesn't need to go through
        // self (avoiding any SwiftUI property-wrapper access on a background thread)
        let delegate = videoCaptureDelegate
        // Read on the main thread (UIKit call); AVFoundation defaults new
        // connections to portrait, so without this landscape recordings come
        // out sideways.
        let recordingOrientation = currentCaptureOrientation()
        ContentView.sessionQueue.async {
            if let connection = videoOutput.connection(with: .video) {
                connection.videoOrientation = recordingOrientation
            }
            delegate.destinationURL = finalURL
            videoOutput.startRecording(to: tmpURL, recordingDelegate: delegate)
        }
    }

    private func stopRecording() {
        guard isRecording, let output = videoOutput else { return }
        isRecording = false
        UIApplication.shared.isIdleTimerDisabled = false
        restoreBrightness()
        // Capture output locally so we don't touch @State from the background thread
        ContentView.sessionQueue.async {
            if output.isRecording {
                output.stopRecording()
                // delegate.fileOutput(_:didFinishRecordingTo:) will fire when done,
                // which moves the temp file → Documents so the Gallery can find it
            }
        }
    }

    // MARK: - Screen Dimming

    private func toggleDim() {
        isScreenDimmed ? wakeScreen() : dimScreen()
    }

    private func dimScreen() {
        savedBrightness = UIScreen.main.brightness
        UIScreen.main.brightness = 0.01   // near-zero for max battery saving
        isScreenDimmed = true
        // Tell RootView to show its full-screen overlay (covers tab bar too)
        NotificationCenter.default.post(name: .screenDidDim, object: nil)
    }

    private func wakeScreen() {
        UIScreen.main.brightness = savedBrightness
        isScreenDimmed = false
        // Tell RootView to hide its overlay and repin tab bar colours
        NotificationCenter.default.post(name: .screenDidWake, object: nil)
    }

    // Called on recording stop / tab switch / background
    private func restoreBrightness() {
        guard isScreenDimmed else { return }
        wakeScreen()
    }

    private func handleRecordingError(_ error: Error?) {
        // Reset state regardless of error type
        isRecording = false
        UIApplication.shared.isIdleTimerDisabled = false

        guard let error = error as NSError? else { return }

        if error.domain == AVFoundationErrorDomain {
            switch AVError.Code(rawValue: error.code) {
            case .diskFull:
                alertTitle = "Storage Full"
                alertMessage = "Recording stopped because your device ran out of storage. The saved footage may be incomplete or unplayable. Free up space before recording again."
            case .maximumFileSizeReached:
                alertTitle = "File Size Limit Reached"
                alertMessage = "Recording stopped because the file reached its maximum size. Your footage has been saved up to this point."
            case .maximumDurationReached:
                alertTitle = "Recording Limit Reached"
                alertMessage = "Recording stopped because the maximum duration was reached. Your footage has been saved up to this point."
            default:
                alertTitle = "Recording Stopped"
                alertMessage = "Recording stopped unexpectedly. The saved footage may be incomplete. Error: \(error.localizedDescription)"
            }
        } else {
            alertTitle = "Recording Stopped"
            alertMessage = "Recording stopped unexpectedly. The saved footage may be incomplete."
        }

        showAlert = true
    }

    // MARK: - Storage

    private func availableStorageMB() -> Int64 {
        let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].path
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: path),
              let freeBytes = attrs[.systemFreeSize] as? Int64 else { return 0 }
        return freeBytes / 1_000_000
    }
}

// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        RootView()
    }
}
