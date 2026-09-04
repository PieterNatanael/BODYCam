import AVFoundation
import MediaPlayer
import UIKit

/// Detects hardware volume-button presses (both Up and Down) and calls `action`.
///
/// Technique:
///   • KVO on `AVAudioSession.outputVolume` — fires on every button press.
///   • An off-screen `MPVolumeView` is added to the key window to suppress the
///     system volume HUD (the view must be in the window hierarchy, not hidden).
///   • After each detected press the volume is silently reset to 0.5 so the
///     user can press again from any starting level.
///   • A `suppressionCount` counter (not a bool) prevents double-firing:
///     every `setVolume` call increments before and decrements 600 ms after,
///     so overlapping resets / silence / restore windows never race each other.
///   • A second, timing-independent guard backs that counter up: every
///     self-inflicted change lands on exactly 0 or 0.5, values a genuine press
///     essentially never reports back (see observeValue). suppressionCount's
///     window is a race against how long iOS takes to deliver the
///     notification for our own change, and that delivery time isn't
///     bounded — a slow enough device taking longer than the window can
///     still lose that race. Checking the reported value itself cannot.
///   • A third guard blocks the action outright for the first couple of
///     seconds after start(), regardless of what any event looks like — see
///     observeValue for why even the value check above isn't the full
///     picture on old hardware.
///   • All state is accessed on the main thread only (KVO handler dispatches
///     to main before touching any state), eliminating data races.
///
/// Works even when the screen is fully dimmed because it relies on hardware
/// events, not touch input.
final class VolumeButtonObserver: NSObject, ObservableObject {

    // MARK: - Private state

    private let audioSession = AVAudioSession.sharedInstance()
    private var volumeView: MPVolumeView?
    private var isObserving     = false
    private var kvoRegistered   = false     // true only after addObserver succeeds
    private var suppressionCount = 0        // >0 → ignore KVO events we generated
    private var lastFiredAt: Date = .distantPast
    private var action: (() -> Void)?
    /// When this instance started observing. Backs the grace-period guard in
    /// observeValue that blocks the action outright for the first couple of
    /// seconds — see there for why this exists on top of suppressionCount
    /// and the value check.
    private var observingStartedAt: Date = .distantPast

    // MARK: - Public interface

    /// Start listening. Call once from `.onAppear`.
    /// All internal state is touched on the main thread.
    func start(action: @escaping () -> Void) {
        guard !isObserving else { return }
        isObserving  = true
        self.action  = action
        observingStartedAt = Date()

        // Ensure the audio session is active so KVO delivers events.
        try? audioSession.setActive(true)

        // MPVolumeView MUST be in the window before we register KVO,
        // so `setVolume` can always find the slider on the first press.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isObserving else { return }

            let vv = MPVolumeView(frame: CGRect(x: -1000, y: -2000, width: 1, height: 1))
            let scene  = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }.first
            let window = scene?.windows.first(where: { $0.isKeyWindow })
                      ?? scene?.windows.first
            window?.addSubview(vv)
            self.volumeView = vv

            // Silently centre volume so both Up and Down are always reachable.
            self.silentReset()

            // Register KVO only now — MPVolumeView is ready so setVolume works.
            self.audioSession.addObserver(self, forKeyPath: "outputVolume",
                                          options: [.new, .old], context: nil)
            self.kvoRegistered = true
        }
    }

    /// Stop listening. Call from `.onDisappear`.
    func stop() {
        guard isObserving else { return }
        isObserving = false
        action      = nil

        // Remove KVO on whichever thread we're on — safe because we only ever
        // added it on the main thread, and removeObserver is thread-safe.
        if kvoRegistered {
            audioSession.removeObserver(self, forKeyPath: "outputVolume")
            kvoRegistered = false
        }

        DispatchQueue.main.async { [weak self] in
            self?.volumeView?.removeFromSuperview()
            self?.volumeView = nil
            self?.suppressionCount = 0
        }
    }

    deinit { stop() }

    // MARK: - KVO

    override func observeValue(forKeyPath keyPath: String?,
                               of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?,
                               context: UnsafeMutableRawPointer?) {
        guard keyPath == "outputVolume" else { return }

        // All state checks happen on the main thread — no data races.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isObserving else { return }

            // Suppress events we generated ourselves (resets, silence, restore).
            guard self.suppressionCount == 0 else { return }

            // A second guard, independent of timing entirely: every change
            // THIS class ever makes lands on exactly 0 (silenceForCapture) or
            // 0.5 (every reset, including the very first one in start()). A
            // genuine physical press instead steps the volume by a hardware
            // notch from wherever it already sits, which — since this class
            // always recentres to 0.5 after handling any event — means a real
            // press essentially never reports back exactly one of these two
            // values.
            //
            // This exists because suppressionCount's fixed timer is a race,
            // not a guarantee: it assumes the "outputVolume changed"
            // notification for our OWN change always arrives within its
            // window, but that delivery isn't instant, and a slow enough
            // device can lose that race. Concretely: a real iPhone 6S,
            // activating its audio session for the very first time on a true
            // cold launch (a genuinely more expensive one-time cost that a
            // background/foreground resume never repeats, which is why this
            // only ever showed up on a full relaunch), sometimes delivered
            // its own start()-time reset late enough to read as a genuine
            // press and silently start recording. A fixed delay before
            // registering KVO was tried first and was not a large enough
            // margin for that specific case — there is no delay that is
            // guaranteed long enough, since the real bound on iOS's own
            // delivery time isn't known. Checking WHAT changed rather than
            // WHEN removes the guesswork entirely.
            if let newVolume = (change?[.newKey] as? NSNumber)?.floatValue,
               newVolume == 0 || abs(newVolume - 0.5) < 0.001 {
                return
            }

            // A third, final guard: a flat couple of seconds after start()
            // during which the action can never fire, no matter what the
            // event looks like. This exists for something neither guard
            // above can fully rule out — confirmed on a real iPhone 6S,
            // where a full device reboot left the very first one or two app
            // launches afterward still auto starting a recording, but never
            // a third launch, and never on an iPhone SE at all. That pattern
            // points to iOS's own audio daemon still settling in after a
            // cold boot on old, slow hardware, not to anything this app
            // itself does — it can apparently report a volume change that
            // matches neither "our own reset" nor "a real press" cleanly
            // enough for the checks above to classify it, before it finishes
            // stabilizing. There's no reported value or timing signature to
            // catch reliably here, because the cause isn't this code.
            //
            // A real person cannot see the camera, decide to record, and
            // physically press a hardware button within the first couple of
            // seconds of the screen even appearing, so unconditionally
            // refusing to act in that window costs nothing in real use while
            // absorbing whatever this settling behaviour does, regardless of
            // what it reports.
            guard Date().timeIntervalSince(self.observingStartedAt) > 2.0 else { return }

            // 300 ms debounce — prevents rapid double-fire from a single press.
            let now = Date()
            guard now.timeIntervalSince(self.lastFiredAt) > 0.3 else { return }
            self.lastFiredAt = now

            // Fire the caller's action (record / capture).
            self.action?()

            // Reset volume back to centre so the button is always reachable
            // regardless of which direction the user pressed.
            self.silentReset()
        }
    }

    // MARK: - Capture silence / restore

    /// Drop volume to 0 before the shutter fires to silence the system sound.
    /// The resulting KVO event is suppressed by the counter.
    /// Must be called on the main thread.
    func silenceForCapture() {
        setVolume(0)
    }

    /// Restore normal volume after capture completes.
    /// The resulting KVO event is suppressed by the counter.
    /// Must be called on the main thread.
    func restoreAfterCapture() {
        setVolume(0.5)
    }

    // MARK: - Helpers

    /// Set system volume via the MPVolumeView slider without showing the HUD.
    ///
    /// `slider.value = x` alone only moves the thumb visually; calling
    /// `sendActions(for: .valueChanged)` is required to actually commit the
    /// change to the iOS audio stack.
    ///
    /// Each call increments `suppressionCount` before touching the slider and
    /// schedules a decrement 200 ms later — after the resulting KVO has fired
    /// and been caught. This means multiple overlapping calls (e.g. an
    /// in-flight reset AND a silenceForCapture) each manage their own window
    /// independently and never clear each other's suppression early.
    ///
    /// Must be called on the main thread.
    private func setVolume(_ value: Float) {
        guard let slider = volumeView?
            .subviews.first(where: { $0 is UISlider }) as? UISlider
        else { return }

        suppressionCount += 1
        slider.value = value
        slider.sendActions(for: .valueChanged)   // commits the change to iOS

        // 0.6s rather than 0.2s. The suppression window has to outlast the
        // delay before our OWN volume change comes back as a KVO event, and
        // that delay stretches under load: a heavy capture (a large photo
        // being re-encoded, say) can push the restore's event past a 200 ms
        // window, at which point the observer no longer recognizes the event
        // as self-inflicted and fires `action` — taking a second photo the
        // user never asked for. The cost of the longer window is that a real
        // button press within 0.6s of a capture is ignored, which is
        // consistent with the 0.3s debounce already applied to genuine
        // presses.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self else { return }
            self.suppressionCount = max(0, self.suppressionCount - 1)
        }
    }

    private func silentReset() { setVolume(0.5) }
}
