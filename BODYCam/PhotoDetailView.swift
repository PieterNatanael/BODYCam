import SwiftUI
import Photos

struct PhotoDetailView: View {
    let item: VideoItem
    var onDelete: () -> Void

    /// False for the pager's off-screen neighbours. Paging TabView builds
    /// adjacent pages ahead of time, so the auto-hide has to start when a page
    /// actually becomes visible — not in onAppear, which fires while it is
    /// still off screen and would leave the chrome already gone on arrival.
    var isActive: Bool = true

    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.presentationMode) private var presentationMode

    @State private var image: UIImage?
    @State private var showDeleteAlert = false
    @State private var showPaywall     = false
    @State private var saveStatus: SaveStatus?
    @State private var scheduleMode: ScheduleMode?
    @AppStorage("AppTheme") private var appThemeRaw: String = AppTheme.simple.rawValue
    private var appTheme: AppTheme { AppTheme(rawValue: appThemeRaw) ?? .normal }
    private var isFlatTheme: Bool { appTheme.isFlat }
    private var accentColor: Color { appTheme.galleryAccent }
    @State private var chromeVisible = true
    /// Set once the first auto-hide has run OR the user has taken manual
    /// control, whichever comes first. After that the chrome only ever moves
    /// by tapping — matching the native gallery, where the timed hide happens
    /// on open and never again.
    @State private var autoHideSpent = false

    enum SaveStatus { case saving, success, failure }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Chrome floats over a full-screen photo rather than sharing space
            // with it. That gives the photo the whole screen to fit into, and
            // means hiding the chrome fades it out instead of reflowing the
            // layout underneath.
            imageArea
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .zoomable(onSingleTap: toggleChrome)

            if chromeVisible {
                VStack(spacing: 0) {
                    topBar.background(topScrim)
                    Spacer()
                    actionBar
                }
                .transition(.opacity)
            }
        }
        .statusBarHidden(!chromeVisible)
        .sheet(isPresented: $showPaywall) {
            PaywallView().environmentObject(subscriptionManager)
        }
        .sheet(item: $scheduleMode) { mode in
            ScheduleSheet(item: item, mode: mode) {}
        }
        .onChange(of: isActive) { active in
            if active { scheduleInitialAutoHide() }
        }
        .onAppear {
            loadImage()
            if isActive { scheduleInitialAutoHide() }
        }
        .alert(isPresented: $showDeleteAlert) {
            Alert(
                title: Text("Delete photo?"),
                message: Text("This cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
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
            Button(action: { presentationMode.wrappedValue.dismiss() }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(isFlatTheme ? accentColor : Color(white: 0.6))
            }
            Spacer()
            Text(formattedDate)
                .font(.caption)
                .foregroundColor(Color(white: 0.5))
            scheduleMenu
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
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

    /// Whole photo, never cropped. With the chrome overlaid rather than taking
    /// space, this now has the full screen to fit into, so it renders far
    /// larger than it did when it was sandwiched between the two bars.
    private var imageArea: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Keeps the close button and date legible over a bright photo.
    private var topScrim: some View {
        LinearGradient(colors: [Color.black.opacity(0.55), Color.black.opacity(0)],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea(edges: .top)
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
        .padding(.vertical, 10)
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
                        .frame(width: 52, height: 52)
                        .shadow(color: locked ? .clear : color.opacity(0.35), radius: 5, x: 0, y: 2)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(locked ? Color(white: 0.38) : color.contrastingForeground)
                }
                if locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                        .foregroundColor(Color(white: 0.55))
                        .offset(x: 2, y: -2)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
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

    private func loadImage() {
        let url = item.url
        DispatchQueue.global(qos: .userInitiated).async {
            let loaded = (try? Data(contentsOf: url)).flatMap { UIImage(data: $0) }
            DispatchQueue.main.async { image = loaded }
        }
    }

    private func saveToPhotos() {
        guard saveStatus == nil else { return }
        saveStatus = .saving
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { saveStatus = .failure }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: item.url)
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
