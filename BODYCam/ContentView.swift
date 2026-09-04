import SwiftUI
import AVFoundation

struct ContentView: View {

    // MARK: - State

    @State private var isRecording = false
    @State private var captureSession: AVCaptureSession?
    @State private var videoOutput: AVCaptureMovieFileOutput?
    @State private var videoURL: URL?
    @AppStorage("SelectedVideoQuality") private var selectedQuality: VideoQuality = .high
    @AppStorage("IsLowLight") private var isLowLight: Bool = false
    /// The rule-of-thirds composition grid, shown over the preview in every
    /// display mode, not just Pro — Pro just happens to be where the one
    /// on-screen toggle button lives. Shared across tabs via AppStorage — a
    /// preference about how you like to frame shots, not something tied to
    /// one tab's own state the way zoom/exposure are. Defaults on: it is a
    /// framing aid, not a destructive or surprising change to what gets
    /// captured, so there is no real downside to a new user having it from
    /// the start.
    @AppStorage("ShowGridLines") private var showGridLines: Bool = true
    @State private var isUsingFront  = false
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
    // LocalizedStringKey rather than String: every assignment site below is
    // a literal (with or without interpolation), which converts to this type
    // automatically, and only this type makes Text(alertTitle)/Text(alertMessage)
    // actually look the value up in Localizable.xcstrings.
    @State private var alertTitle: LocalizedStringKey = ""
    @State private var alertMessage: LocalizedStringKey = ""
    @State private var showAlert = false
    @State private var isScreenDimmed = false
    @State private var savedBrightness: CGFloat = UIScreen.main.brightness
    @State private var showAppSettingsSheet = false
    /// Whether this tab is currently on screen. Camera setup is asynchronous
    /// and slow (1 to 3 seconds), so the user can easily leave before it
    /// finishes — see setupCaptureSession's completion block.
    @State private var isTabVisible = false
    /// Wall-clock start of the current recording. Elapsed time is derived from
    /// this rather than counted up tick by tick, so a missed or late tick can
    /// never make the displayed duration drift away from the real one.
    @State private var recordingStartedAt: Date?
    @State private var elapsed: TimeInterval = 0
    private let recordingTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @AppStorage("CameraDisplayMode") private var displayModeRaw: String = CameraDisplayMode.saveBattery.rawValue
    private var displayMode: CameraDisplayMode { CameraDisplayMode(rawValue: displayModeRaw) ?? .saveBattery }
    // Yapping mode: script text takes the main area, the camera preview
    // shrinks to a small draggable corner window instead. Text persists
    // across launches like everything else here; the PiP's position is
    // session only — resetting to a sensible default corner each time this
    // view is rebuilt is simpler than persisting a point that has to stay
    // valid across every screen size the app runs on.
    // Default only ever shows up before someone's typed or pasted anything of
    // their own — once yappingText is written to even once, this literal
    // never appears again for that user, on this device.
    // This is stored data in an editable TextEditor, not a label, so there's
    // no Text() call site to hang a LocalizedStringKey lookup off — the
    // lookup has to happen right here, once, when this default is first
    // evaluated. Bundle.appPreferred.localizedString rather than the bare
    // NSLocalizedString function specifically so this respects an in-app
    // language override too, not just the device's own system language.
    @AppStorage("YappingScriptText") private var yappingText: String =
        Bundle.appPreferred.localizedString(
            forKey: "Replace this with your own text. Type or paste your script here. Press CLEAR to erase this text and start fresh.",
            value: nil, table: nil)
    @AppStorage("YappingNarrowColumn") private var yappingNarrow: Bool = false
    @State private var yappingPipCenter: CGPoint?
    @GestureState private var yappingPipDrag: CGSize = .zero
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
    private var recordAccent: Color { appTheme.recordAccent }
    private var previewAccent: Color { appTheme.previewAccent }

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
    //
    // This USED to be its own separate queue from PhotoCameraView's. Now
    // points at the queue shared with it instead — see
    // sharedCameraSessionQueue's own comment in CameraPreviewView.swift for
    // why two independent queues here was a real, confirmed bug, not just a
    // theoretical one.
    private static let sessionQueue = sharedCameraSessionQueue

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
            // record row itself — so the reserve here is much smaller than
            // portrait's.
            let reserved: CGFloat = isCompact ? 90 : 110
            return effectiveScreenSize.height - reserved
        }
        let natural: CGFloat = (effectiveScreenSize.width - 48) * 4 / 3
        let reserved: CGFloat = isCompact ? 260 : 300
        return min(natural, effectiveScreenSize.height - reserved)
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

            // Behind the preview rather than replacing it — the live preview
            // stays the single shared instance below regardless of mode (see
            // sharedPreviewLayer), so this can come and go freely without
            // ever tearing down and recreating the expensive camera layer.
            if displayMode == .yapping {
                yappingTextArea
            }

            sharedPreviewLayer

            // Top chrome differs by mode, but the record row (record button,
            // flip/dim/settings) is a single shared view below — previously each
            // mode had its own copy, and small layout differences between them
            // caused the record row to shift and clip behind the tab bar in
            // Normal mode. Sharing it guarantees an identical position always.
            VStack(spacing: 0) {
                topChrome
                Spacer(minLength: 0)
                if displayMode == .yapping {
                    // Same leading padding as flip/dim below, so this sits
                    // directly above that cluster rather than the text area's
                    // own top, where it used to compete with the Premium badge.
                    HStack(spacing: 10) {
                        yappingChip(title: "CLEAR", icon: "xmark.circle") { yappingText = "" }
                        yappingChip(title: yappingNarrow ? "WIDE" : "NARROW",
                                   icon: yappingNarrow ? "arrow.left.and.right" : "arrow.right.and.left") {
                            yappingNarrow.toggle()
                        }
                        Spacer()
                    }
                    .padding(.leading, 20)
                    .padding(.bottom, 10)
                }
                if displayMode == .pro {
                    proControlsPanel
                        .padding(.horizontal, 20)
                        .padding(.bottom, 10)
                }
                recordRow
                    .padding(.bottom, bottomPad)
            }

            // Overlaid rather than placed in the VStack above. The old REC
            // indicator sat in that stack, so it resized the preview every time
            // recording started or stopped — this can't, because it takes no
            // part in the layout.
            VStack {
                if isRecording {
                    recordingTimerBadge
                        .padding(.top, 6)
                        .transition(.opacity)
                }
                Spacer()
            }
            .animation(.easeInOut(duration: 0.2), value: isRecording)
        }
        .onReceive(recordingTimer) { _ in
            // Guarded so nothing is written (and no redraw happens) when idle.
            guard isRecording, let start = recordingStartedAt else { return }
            elapsed = Date().timeIntervalSince(start)
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
            // Explicit, not via stopRecording — that early-returns unless a
            // recording is in progress, so dimming without recording and then
            // leaving would strand the screen at 1% brightness (and now the
            // preview connection switched off with it).
            restoreBrightness()
            volumeObserver.stop()
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
            // Stop the session so the Camera tab (or any other consumer)
            // can claim the hardware. iOS cannot run two sessions at once.
            let session = captureSession
            ContentView.sessionQueue.async { session?.stopRunning() }

            // AVCaptureDevice.default(...) does not hand back a fresh object
            // per session — it returns the SAME physical camera every time,
            // and zoom/exposure bias/focus-exposure mode all live ON that
            // device, not on the session or input. Stopping the session above
            // does nothing to any of that, so without this, a manual
            // adjustment made here would still be sitting on the hardware the
            // next time the Photo tab claims it — even though ITS OWN zoom
            // readout, EV slider, and lock button all show neutral, because
            // each tab's @State only knows what IT set, never what the other
            // tab left behind.
            resetManualCameraAdjustments(session: session, on: ContentView.sessionQueue)
            // The readouts themselves also need to go back to neutral here,
            // not just the device — this tab's own @State persists across a
            // tab switch (SwiftUI keeps every tab's view alive), so without
            // this, returning later would show a stale "3.0x"/"-1.5" that no
            // longer matches the hardware this just put back to neutral.
            zoomFactor = 1.0
            exposureBias = 0
            isAutoLocked = false
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            stopRecording()
            // Screen brightness is a system-wide setting that survives the app,
            // so backgrounding while dimmed would otherwise leave the user's
            // phone at 1% until they fixed it themselves.
            restoreBrightness()
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
                guard let session = captureSession else { return }
                ContentView.applyQuality(newValue, to: session)
            }
        }
        .onChange(of: isLowLight) { newValue in
            applyLowLight(newValue)
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
            applyExposureBias(0, session: captureSession, on: ContentView.sessionQueue) { applied in
                exposureBias = applied
            }
            setAutoLock(false, session: captureSession, on: ContentView.sessionQueue)
            isAutoLocked = false
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
            if let glow = appTheme.cameraBackgroundGlow, displayMode == .saveBattery || displayMode == .pro {
                // Relevant in Save Battery and Pro: both use the same centered
                // card, unlike Normal (fills the screen) or Yapping (shares it
                // with script text), so those two are the only modes where a
                // background glow is ever actually visible around it.
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
            // The one spot in the top strip with genuinely free space:
            // Normal and Yapping fill or share this area, and Save Battery
            // has nothing of its own to put here — Pro mode does.
            if displayMode == .pro {
                gridToggleButton
                    .padding(.leading)
            }

            Spacer()

            // Go Pro button — hidden once subscribed
            if !subscriptionManager.isUnlocked {
                goProBadge
                    .padding(.trailing)
            }
        }
        .padding(.vertical, 8)
    }

    /// Elapsed recording time, so it's unmistakable that recording is running.
    private var recordingTimerBadge: some View {
        HStack(spacing: 7) {
            // Blink is driven off the same one-second tick that updates the
            // clock, rather than a repeatForever animation — no separate
            // always-running animation just to pulse a dot.
            Circle()
                .fill(Color.white)
                .frame(width: 7, height: 7)
                .opacity(Int(elapsed) % 2 == 0 ? 1 : 0.3)
                .animation(.easeInOut(duration: 0.3), value: Int(elapsed) % 2)

            Text(elapsedText)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.red))
        .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
    }

    private var elapsedText: String {
        let total = max(0, Int(elapsed))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
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
            let isYapping = displayMode == .yapping
            let topInset = geo.safeAreaInsets.top
            let bottomInset = geo.safeAreaInsets.bottom

            // Yapping's PiP center, draggable and clamped to stay fully on
            // screen. Computed unconditionally (cheap) so the modifier chain
            // below never has to branch in a way that would change the
            // preview's view identity between modes.
            let pipSize = CGSize(width: 108, height: 148)
            let pipBaseCenter = yappingPipCenter
                ?? CGPoint(x: geo.size.width - pipSize.width / 2 - 16, y: geo.size.height * 0.2)
            let pipLiveCenter = CGPoint(x: pipBaseCenter.x + yappingPipDrag.width,
                                        y: pipBaseCenter.y + yappingPipDrag.height)
            let pipClampedCenter = CGPoint(
                x: min(max(pipLiveCenter.x, pipSize.width / 2), geo.size.width - pipSize.width / 2),
                y: min(max(pipLiveCenter.y, pipSize.height / 2), geo.size.height - pipSize.height / 2))

            let w: CGFloat = isYapping ? pipSize.width : isNormal
                ? geo.size.width + geo.safeAreaInsets.leading + geo.safeAreaInsets.trailing
                : previewCardWidth
            let h: CGFloat = isYapping ? pipSize.height : isNormal ? geo.size.height + topInset + bottomInset : previewCardHeight
            // An offset FROM the ZStack's default centered position, rather
            // than an absolute .position(). .position() makes a view greedy
            // for its parent's proposed size before placing it, which doesn't
            // compose with ignoresSafeArea() the same way .offset() does —
            // using it here left Normal mode's bleed short at the bottom
            // edge, a thin black strip where the tab bar used to be covered.
            // .offset() is what the original, working Normal/Save Battery
            // logic used, so Yapping's drag is expressed the same way: as the
            // offset from center that lands the PiP at its dragged point.
            let offset: CGSize = isYapping
                ? CGSize(width: pipClampedCenter.x - geo.size.width / 2,
                        height: pipClampedCenter.y - geo.size.height / 2)
                : CGSize(width: 0, height: isNormal ? (bottomInset - topInset) / 2 : 0)
            let radius: CGFloat = isYapping ? 10 : isNormal ? 0 : previewCornerRadius
            let borderColor: Color = isYapping ? Color.white.opacity(0.55) : isNormal ? Color.clear : previewBorderColor
            let borderWidth: CGFloat = isYapping ? 1.5 : isNormal ? 0 : previewBorderWidth
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
                    // (wake tap, stop recording, tab switch, backgrounding)
                    // re-enables the preview automatically — there's no path
                    // that can leave it stuck off.
                    CameraPreviewView(
                        session: session,
                        isPreviewActive: !isScreenDimmed,
                        onFocusTap: { devicePoint in
                            applyTapToFocus(session: captureSession,
                                            devicePoint: devicePoint,
                                            on: ContentView.sessionQueue)
                        },
                        onPinchZoom: { requested in
                            applyZoom(requested, session: captureSession, on: ContentView.sessionQueue) { applied in
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
                    // Always attached, content only varies with showGridLines
                    // — same reasoning as previewBorderOverlay just above:
                    // keeping the modifier itself unconditional is what keeps
                    // CameraPreviewView's identity (and the fast mode
                    // switching that depends on it) stable.
                    .overlay(gridLinesOverlay)
                    .shadow(color: isYapping ? .black.opacity(0.5) : .clear, radius: isYapping ? 6 : 0, x: 0, y: 3)
                    .offset(offset)
                    .ignoresSafeArea(.all, edges: isNormal ? .all : [])
                    // A drag can never actually be recognized outside Yapping
                    // — the minimum distance is effectively infinite — so this
                    // is always attached rather than conditionally, keeping
                    // the view identity above stable across every mode switch.
                    // That stability is what makes switching fast; a
                    // conditionally attached gesture doesn't itself break it,
                    // but a conditionally attached VIEW upstream of it would.
                    .gesture(
                        DragGesture(minimumDistance: isYapping ? 0 : 100_000)
                            .updating($yappingPipDrag) { value, state, _ in state = value.translation }
                            .onEnded { value in
                                guard isYapping else { return }
                                let moved = CGPoint(x: pipBaseCenter.x + value.translation.width,
                                                    y: pipBaseCenter.y + value.translation.height)
                                yappingPipCenter = CGPoint(
                                    x: min(max(moved.x, pipSize.width / 2), geo.size.width - pipSize.width / 2),
                                    y: min(max(moved.y, pipSize.height / 2), geo.size.height - pipSize.height / 2))
                            }
                    )
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
                    .offset(offset)
                    .ignoresSafeArea(.all, edges: isNormal ? .all : [])
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    /// Re-reads the attached camera's true exposure bias range. Called after
    /// initial setup and after every flip, since the front and back cameras
    /// commonly report DIFFERENT ranges from each other.
    private func refreshExposureBiasRange(session: AVCaptureSession?) {
        currentExposureBiasRange(session: session, on: ContentView.sessionQueue) { range in
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
    // control strip above the record row, so the two panel exposure and
    // lock controls at the moments they're actually useful: before or during
    // a recording, without needing to leave the camera screen.

    /// Lives in the top strip rather than the bottom panel with exposure/lock
    /// — that panel is about the moment right before or during recording,
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
                        applyExposureBias(newValue, session: captureSession, on: ContentView.sessionQueue) { applied in
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
                setAutoLock(isAutoLocked, session: captureSession, on: ContentView.sessionQueue)
            }) {
                HStack(spacing: 6) {
                    Image(systemName: isAutoLocked ? "lock.fill" : "lock.open.fill")
                    // .tracking() applied here, not on the enclosing HStack:
                    // Text has its own dedicated tracking modifier available
                    // back to this app's iOS 14 floor, while the generic
                    // View.tracking(_:) that an HStack would resolve to needs
                    // iOS 16.
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

    // MARK: - Yapping mode
    //
    // A script fills the screen so it reads like a teleprompter, and the live
    // camera preview (still the single shared instance above) shrinks to a
    // small window the user can drag out of the way of whatever they're
    // reading. Recording itself is untouched — same session, same record
    // button below — this only changes what's on screen above it.

    private var yappingTextArea: some View {
        VStack(spacing: 10) {
            yappingToolbar
            yappingTextEditor
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
    }

    @ViewBuilder
    private var yappingTextEditor: some View {
        let editor = TextEditor(text: $yappingText)
            .font(.system(size: yappingNarrow ? 26 : 22, weight: .semibold, design: .rounded))
            .foregroundColor(.white)
            .frame(maxWidth: yappingNarrow ? UIScreen.main.bounds.width * 0.62 : .infinity)
            .padding(.horizontal, yappingNarrow ? 0 : 16)
            .padding(.bottom, 140) // keeps the last lines clear of the record row

        // .toolbar(placement: .keyboard) needs iOS 15, so Done sits in a
        // keyboard accessory bar there — right above the keyboard, appearing
        // only while it's up, rather than sharing the top row with the
        // Premium badge where the two were colliding. Below iOS 15 it falls
        // back to always being visible at the top, same as before.
        if #available(iOS 16.0, *) {
            editor
                .scrollContentBackground(.hidden)
                .background(Color.black)
                .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); doneKeyboardButton } }
        } else if #available(iOS 15.0, *) {
            editor
                .background(Color.black)
                .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); doneKeyboardButton } }
        } else {
            editor.background(Color.black)
        }
    }

    private var doneKeyboardButton: some View {
        Button(action: {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                            to: nil, from: nil, for: nil)
        }) {
            Text("Done").font(.system(size: 15, weight: .bold))
        }
    }

    // Only reachable below iOS 15, where there's no keyboard toolbar to put
    // Done in instead — see yappingTextEditor. Clear and Narrow moved down to
    // sit above the flip/dim buttons instead — see body.
    @ViewBuilder
    private var yappingToolbar: some View {
        if #unavailable(iOS 15.0) {
            HStack {
                Spacer()
                yappingChip(title: "DONE", icon: "keyboard.chevron.compact.down") {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                    to: nil, from: nil, for: nil)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func yappingChip(title: LocalizedStringKey, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11))
                Text(title).font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(1)
            }
            .foregroundColor(Color(white: 0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.2))
                    RoundedRectangle(cornerRadius: 6).stroke(Color(white: 0.45), lineWidth: 1)
                }
            )
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
                HStack(spacing: 10) {
                    zoomButton
                    settingsButton
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
            applyZoom(1.0, session: session, on: ContentView.sessionQueue) { applied in
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
        // The device being attached below always starts at 1x regardless of
        // what the outgoing camera was zoomed to, so the readout follows suit
        // immediately rather than showing a stale value from the old camera.
        zoomFactor = 1.0
        exposureBias = 0
        isAutoLocked = false
        let position: AVCaptureDevice.Position = isUsingFront ? .front : .back

        ContentView.sessionQueue.async {
            session.beginConfiguration()
            // Remove only video inputs — keep the audio input
            let previousInputs = session.inputs.compactMap { $0 as? AVCaptureDeviceInput }
                .filter { $0.device.hasMediaType(.video) }
            for input in previousInputs { session.removeInput(input) }

            // Drop to a preset both cameras support BEFORE attempting to
            // attach the new one, because canAddInput below is evaluated
            // against the session's CURRENT preset.
            //
            // This is the whole Max-only bug: Low/Medium/High resolve to
            // presets every camera supports, but Max asks for the largest the
            // DEVICE accepts, and the two cameras don't accept the same set —
            // the back camera commonly does 4K while the front tops out at
            // 1080p. With 4K still set from the back camera, adding the front
            // camera failed canAddInput outright, and the early return then
            // committed a session with NO video input at all. That's why the
            // preview went fully black rather than merely looking wrong, and
            // why switching to High first worked around it.
            session.sessionPreset = .high

            guard
                let device = bestCaptureDevice(position: position),
                let newInput = try? AVCaptureDeviceInput(device: device),
                session.canAddInput(newInput)
            else {
                // Put the previous camera back, so a flip that can't happen
                // degrades to "nothing changed" instead of a dead preview.
                for input in previousInputs where session.canAddInput(input) {
                    session.addInput(input)
                }
                session.commitConfiguration()
                ContentView.applyQuality(self.selectedQuality, to: session)
                // Undo the optimistic toggle, or the button would claim to be
                // showing a camera that was never actually attached.
                DispatchQueue.main.async { self.isUsingFront.toggle() }
                return
            }
            session.addInput(newInput)
            session.commitConfiguration()

            // Now re-evaluate the preset against the camera that's actually
            // attached, so Max climbs back to whatever THIS one can do.
            ContentView.applyQuality(self.selectedQuality, to: session)

            // Otherwise the newly selected camera inherits the previous one's
            // tap-to-focus point, which rarely makes sense for a different lens.
            resetFocusToContinuous(session: session, on: ContentView.sessionQueue)

            // The front and back cameras commonly report DIFFERENT exposure
            // bias ranges, so this can't just be reset to a fixed default —
            // it has to be re-read from whichever camera is now attached.
            DispatchQueue.main.async { self.refreshExposureBiasRange(session: session) }
        }
    }

    // `overrideSession` exists for setupCaptureSession's own call: at that
    // point the local `session` it just built isn't assigned to the
    // `captureSession` @State property yet (that happens afterward, back on
    // the main queue), so relying on self.captureSession there would read nil
    // and silently skip applying the saved setting on every launch.
    private func applyLowLight(_ enabled: Bool, overrideSession: AVCaptureSession? = nil) {
        // The session's OWN current device, not the system's generic default
        // — those silently stopped being the same object once the back
        // camera started resolving to the virtual multi-lens device, and were
        // never the same object at all on the front camera. Configuring the
        // wrong AVCaptureDevice instance does nothing to the one actually
        // attached, so this toggle would have quietly no-opped in both cases.
        guard let device = (overrideSession ?? captureSession)?.inputs
            .compactMap({ $0 as? AVCaptureDeviceInput })
            .first(where: { $0.device.hasMediaType(.video) })?.device
        else { return }
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

            guard let videoDevice = bestCaptureDevice(position: .back),
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

            ContentView.applyQuality(self.selectedQuality, to: session)

            session.startRunning()

            // Apply saved low light setting after session starts
            self.applyLowLight(self.isLowLight, overrideSession: session)

            DispatchQueue.main.async {
                self.videoOutput = output
                self.captureSession = session
                self.refreshExposureBiasRange(session: session)

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

    // MARK: - Quality

    /// Applies the selected tier to a running session. Every tier but Max uses
    /// its own fixed preset; Max asks for the largest video preset this
    /// particular device will accept, so better hardware genuinely gets more.
    /// Static, and takes the session explicitly, so it can run from the
    /// session queue without capturing `self`.
    private static func applyQuality(_ quality: VideoQuality, to session: AVCaptureSession) {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard quality == .max else {
            session.sessionPreset = quality.preset
            return
        }

        // Deliberately preset based rather than scanning device.formats for
        // the most pixels. That scan is what made Max letterboxed: the 12MP
        // stills format (4032x3024) has MORE total pixels than 4K, and it also
        // advertises 30fps video support, so neither a pixel count nor a frame
        // rate filter excludes it — it just quietly won, and recorded 4:3 while
        // every other tier recorded 16:9.
        //
        // These presets are defined as video formats, so the aspect ratio is
        // correct by construction. Ordered largest first; canSetSessionPreset
        // is what makes this device relative, giving capable hardware 4K and
        // letting older hardware fall through to what it can actually do.
        for preset in [AVCaptureSession.Preset.hd4K3840x2160,
                       .hd1920x1080,
                       .high] where session.canSetSessionPreset(preset) {
            session.sessionPreset = preset
            return
        }
        session.sessionPreset = quality.preset
    }

    // MARK: - Recording

    private func startRecording() {
        guard let videoOutput else { return }

        // Check available storage before starting. The minimum scales with
        // quality: Max can run several MB per second, so the same 50MB
        // cushion that's plenty for Low would let the framework's own end of
        // disk safety stop cut the recording off within seconds.
        let freeMB = availableStorageMB()
        let requiredMB = selectedQuality.minRecordingStorageMB
        guard freeMB > requiredMB else {
            alertTitle = "Not Enough Storage"
            alertMessage = freeMB <= 0
                ? "Unable to determine available storage. Free up space and try again."
                : "Only \(freeMB) MB remaining. \(selectedQuality.shortLabel) quality needs at least \(requiredMB) MB free. Free up storage space or lower the quality before recording."
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
        recordingStartedAt = Date()
        elapsed = 0
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
        recordingStartedAt = nil
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
