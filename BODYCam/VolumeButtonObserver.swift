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
///     every `setVolume` call increments before and decrements 200 ms after,
///     so overlapping resets / silence / restore windows never race each other.
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

    // MARK: - Public interface

    /// Start listening. Call once from `.onAppear`.
    /// All internal state is touched on the main thread.
    func start(action: @escaping () -> Void) {
        guard !isObserving else { return }
        isObserving  = true
        self.action  = action

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

            // KVO registration is delayed, not immediate, specifically
            // because of the reset just above: it changes the real system
            // volume, and the "outputVolume changed" notification for that
            // isn't delivered instantly — there is a real, variable gap
            // before iOS reports it back. suppressionCount alone races that
            // gap against a timer, and a slow enough device can lose that
            // race: a real iPhone 6S, under the extra CPU load of a cold
            // launch, occasionally delivered it more than 600 ms late — past
            // the point suppressionCount had already cleared — at which
            // point it read as a genuine button press and silently started
            // recording the moment the app opened. An iPhone SE never showed
            // this because it is fast enough to always land inside that
            // window.
            //
            // Not observing AT ALL until well after this specific reset has
            // had time to fully propagate means there is no listener present
            // to ever misinterpret it, however late it arrives — a real fix
            // rather than a wider window that just makes the same race less
            // likely. The only cost is volume-button-to-record being
            // unavailable for this one second right as the tab opens, which
            // is not something anyone presses into that fast.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self, self.isObserving, !self.kvoRegistered else { return }
                self.audioSession.addObserver(self, forKeyPath: "outputVolume",
                                              options: [.new, .old], context: nil)
                self.kvoRegistered = true
            }
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
