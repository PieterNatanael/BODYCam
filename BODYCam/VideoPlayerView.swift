import SwiftUI
import AVKit
import Photos
import Combine

struct VideoPlayerView: View {
    let item: VideoItem
    var onDelete: () -> Void

    /// False for the pager's off-screen neighbours. Paging TabView keeps
    /// adjacent pages alive, so without this every nearby video would start
    /// playing at once and their audio would pile up.
    var isActive: Bool = true

    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.presentationMode) private var presentationMode

    @State private var player: AVPlayer?
    @State private var showDeleteAlert = false
    @State private var showPaywall     = false
    @State private var saveStatus: SaveStatus?
    @State private var scheduleMode: ScheduleMode?
    @AppStorage("AppTheme") private var appThemeRaw: String = AppTheme.tropical.rawValue
    private var appTheme: AppTheme { AppTheme(rawValue: appThemeRaw) ?? .normal }
    private var isFlatTheme: Bool { appTheme.isFlat }
    private var accentColor: Color { appTheme.galleryAccent }
    @State private var chromeVisible = true
    /// Set once the first auto-hide has run OR the user has taken manual
    /// control, whichever comes first. After that the chrome only ever moves
    /// by tapping — matching the native gallery, where the timed hide happens
    /// on open and never again.
    @State private var autoHideSpent = false
    /// Persisted, so someone who wants looping doesn't have to re-enable it
    /// for every clip.
    @AppStorage("LoopVideoPlayback") private var loopPlayback = true

    enum SaveStatus { case saving, success, failure }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Unlike the photo viewer, the chrome is NOT overlaid on top of the
            // video while it's showing. AVKit draws its own transport controls
            // along the bottom of the player, so a floating action bar would
            // land straight on top of the scrubber. Insetting the video while
            // the chrome is up keeps the two sets of controls apart, and the
            // video still goes fully edge to edge in the state that matters —
            // chrome hidden, which is where you watch from.
            VStack(spacing: 0) {
                if chromeVisible {
                    topBar
                }
                playerArea
                if chromeVisible {
                    actionBar
                }
            }
            .ignoresSafeArea(edges: chromeVisible ? [] : .all)
        }
        .statusBarHidden(!chromeVisible)
        .sheet(isPresented: $showPaywall) {
            PaywallView().environmentObject(subscriptionManager)
        }
        .sheet(item: $scheduleMode) { mode in
            ScheduleSheet(item: item, mode: mode) {}
        }
        .onAppear {
            let newPlayer = AVPlayer(url: item.url)
            player = newPlayer
            if isActive {
                newPlayer.play()
                scheduleInitialAutoHide()
            }
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
        // Swiping between pages in the gallery pager makes this page active or
        // inactive without it ever appearing/disappearing, so playback has to
        // follow the selection rather than the view lifecycle.
        .onChange(of: isActive) { active in
            if active {
                player?.play()
                scheduleInitialAutoHide()
            } else {
                player?.pause()
            }
        }
        // AVPlayer pauses itself when the audio session is interrupted and never
        // resumes on its own, so without this the video just sits there until
        // the user taps play. Interruptions here come from phone calls and Siri,
        // and previously from this app's own camera session starting up behind
        // the Gallery — see setupCaptureSession in ContentView.
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended,
                  // Don't resume a page the user has swiped away from, and
                  // don't fight the free-tier cap that deliberately paused us.
                  isActive, !showPaywall
            else { return }
            try? AVAudioSession.sharedInstance().setActive(true)
            player?.play()
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { note in
            // This publisher fires for every player item in the process, so
            // check identity — otherwise a neighbouring page finishing would
            // restart this one.
            guard loopPlayback,
                  let finished = note.object as? AVPlayerItem,
                  finished === player?.currentItem else { return }
            player?.seek(to: .zero)
            player?.play()
        }
        .alert(isPresented: $showDeleteAlert) {
            Alert(
                title: Text("Delete video?"),
                message: Text("This cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    player?.pause()
                    onDelete()
                    presentationMode.wrappedValue.dismiss()
                },
                secondaryButton: .cancel()
            )
        }
    }

    // MARK: - Sub-views

    private var topBar: some View {
        HStack {
            Button(action: {
                player?.pause()
                presentationMode.wrappedValue.dismiss()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(isFlatTheme ? accentColor : Color(white: 0.6))
            }
            Spacer()
            Text(formattedDate)
                .font(.caption)
                .foregroundColor(Color(white: 0.5))
            loopButton
            scheduleMenu
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    /// Tinted when on, so the current state is readable without opening a menu.
    private var loopButton: some View {
        Button(action: { loopPlayback.toggle() }) {
            Image(systemName: "repeat")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(loopPlayback ? (isFlatTheme ? accentColor : .white)
                                               : Color(white: 0.35))
                .padding(.leading, 14)
        }
    }

    private var scheduleMenu: some View {
        Menu {
            Button {
                scheduleMode = .alarm
            } label: {
                Label(ScheduleMode.alarm.title, systemImage: ScheduleMode.alarm.systemImage)
            }
            Button {
                scheduleMode = .reminder
            } label: {
                Label(ScheduleMode.reminder.title, systemImage: ScheduleMode.reminder.systemImage)
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 22))
                .foregroundColor(isFlatTheme ? accentColor : Color(white: 0.6))
                .padding(.leading, 12)
        }
    }

    private var playerArea: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
                    // zoomable's own tap handling is layered with
                    // simultaneousGesture, not an exclusive one — AVKit still
                    // owns taps in this area for its own play/pause and
                    // scrubber, so both fire, and our chrome toggles at the
                    // same moment AVKit shows or hides its own controls.
                    .zoomable(onSingleTap: toggleChrome)
            }
        }
    }

    // MARK: - Chrome visibility

    private func toggleChrome() {
        // Any manual tap also cancels a still-pending initial auto-hide, so the
        // chrome can't vanish a moment after the user deliberately brought it back.
        autoHideSpent = true
        withAnimation(.easeInOut(duration: 0.25)) { chromeVisible.toggle() }
    }

    private func scheduleInitialAutoHide() {
        guard !autoHideSpent else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            guard !autoHideSpent, isActive else { return }
            autoHideSpent = true
            withAnimation(.easeInOut(duration: 0.25)) { chromeVisible = false }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 0) {
            // Save — locked for free users
            actionButton(
                icon: saveIcon,
                label: saveLabel,
                color: saveTint,
                locked: !subscriptionManager.isUnlocked
            ) {
                if subscriptionManager.isUnlocked { saveToPhotos() }
                else { showPaywall = true }
            }

            // Share — locked for free users
            actionButton(
                icon: "square.and.arrow.up",
                label: "Share",
                color: isFlatTheme ? accentColor : .lightGray,
                locked: !subscriptionManager.isUnlocked
            ) {
                if subscriptionManager.isUnlocked { share() }
                else { showPaywall = true }
            }

            // Delete — always available
            actionButton(icon: "trash", label: "Delete",
                         color: .red, locked: false) {
                showDeleteAlert = true
            }
        }
        // Reduced from 10 to match PhotoDetailView's identical bar — this is
        // a solid, opaque overlay sitting ON TOP of the full-bleed media
        // underneath, not sharing layout space with it, so every point of
        // its own height hides a point of the frame behind it while the
        // chrome is showing.
        .padding(.vertical, 6)
        .background(Color(white: 0.08))
    }

    private func actionButton(icon: String, label: LocalizedStringKey,
                               color: Color, locked: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    // Locked keeps the dark, outlined treatment — a solid bright
                    // circle would read as enabled and invite the tap it refuses.
                    Circle()
                        .fill(locked ? Color(white: 0.14) : color)
                        .overlay(
                            Circle().stroke(locked ? Color(white: 0.3) : Color.white.opacity(0.18),
                                            lineWidth: 1)
                        )
                        // 44, not 52 — still Apple's own minimum comfortable
                        // touch target, matching PhotoDetailView's bar.
                        .frame(width: 44, height: 44)
                        .shadow(color: locked ? .clear : color.opacity(0.35), radius: 4, x: 0, y: 2)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(locked ? Color(white: 0.38) : color.contrastingForeground)
                }
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8))
                        .foregroundColor(Color(white: 0.55))
                        .offset(x: 1, y: -1)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        // The visible caption is gone, so carry it for VoiceOver instead —
        // otherwise these become three unlabelled buttons.
        .accessibilityLabel(label)
    }

    // MARK: - Computed helpers

    private var formattedDate: String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: item.url.path)
        let date = attrs?[.creationDate] as? Date ?? Date()
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    private var saveIcon: String {
        switch saveStatus {
        case .saving:  return "arrow.triangle.2.circlepath"
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.circle.fill"
        case nil:      return "square.and.arrow.down.fill"
        }
    }

    private var saveLabel: LocalizedStringKey {
        switch saveStatus {
        case .saving:  return "Saving…"
        case .success: return "Saved!"
        case .failure: return "Failed"
        case nil:      return "Save"
        }
    }

    private var saveTint: Color {
        switch saveStatus {
        case .success: return .green
        case .failure: return .red
        default:       return isFlatTheme ? accentColor : .lightGray
        }
    }

    // MARK: - Actions

    private func saveToPhotos() {
        guard saveStatus == nil else { return }
        saveStatus = .saving
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { saveStatus = .failure }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: item.url)
            }) { success, _ in
                DispatchQueue.main.async {
                    saveStatus = success ? .success : .failure
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saveStatus = nil }
                }
            }
        }
    }

    private func share() {
        let activityVC = UIActivityViewController(
            activityItems: [item.url], applicationActivities: nil)
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }

        // Required on iPad, where a share sheet is a popover: presenting one
        // with no anchor raises rather than falling back to a sheet. This app
        // declares iPad orientations, so it is genuinely reachable there.
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX,
                                        y: top.view.bounds.maxY - 60,
                                        width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        top.present(activityVC, animated: true)
    }
}
