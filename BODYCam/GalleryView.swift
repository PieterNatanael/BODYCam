import SwiftUI

struct GalleryView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @State private var videos: [VideoItem] = []
    @State private var selectedVideo: VideoItem?
    /// Both delete confirmations run through ONE alert.
    ///
    /// Two separate .alert(isPresented:) modifiers in the same hierarchy do
    /// not both work: when an ancestor already has one, a descendant's is
    /// silently ignored — the button visibly reacts and then nothing appears.
    /// The sheets in this file dodge that by living on different subviews,
    /// but alerts don't tolerate the same trick, so single and batch share a
    /// single .alert(item:) on the root instead.
    @State private var pendingDelete: PendingDelete?
    @State private var showPaywall = false
    @ObservedObject private var notificationRouter = NotificationRouter.shared
    @ObservedObject private var scheduleStore = ScheduleStore.shared
    @State private var showScheduledList = false
    /// Multi-select mode, modelled on the native gallery: entering it turns
    /// taps into selection toggles rather than "open this item".
    @State private var isSelecting = false
    /// Keyed by VideoItem.id (the file URL) rather than by index, so the set
    /// stays correct if the list is reloaded or reordered underneath it —
    /// which happens whenever a recording is added or deleted.
    @State private var selectedIDs: Set<URL> = []
    @AppStorage("AppTheme") private var appThemeRaw: String = AppTheme.simple.rawValue
    private var appTheme: AppTheme { AppTheme(rawValue: appThemeRaw) ?? .normal }
    private var isFlatTheme: Bool { appTheme.isFlat }
    private var accentColor: Color { appTheme.galleryAccent }

    // Simple/Tactical widens the grid gutter so the grid structure itself
    // reads as a design element, Bauhaus-style, rather than an afterthought.
    private var gridSpacing: CGFloat { isFlatTheme ? 8 : 3 }
    private var columns: [GridItem] {
        [GridItem(.flexible(), spacing: gridSpacing),
         GridItem(.flexible(), spacing: gridSpacing)]
    }

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                header

                if videos.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: gridSpacing) {
                            ForEach(videos) { video in
                                VideoThumbnailCard(item: video)
                                    .overlay(selectionOverlay(for: video))
                                    .onTapGesture {
                                        if isSelecting {
                                            toggleSelection(video)
                                        } else {
                                            selectedVideo = video
                                        }
                                    }
                                    // Suppressed while selecting: a long press
                                    // offering to delete ONE item contradicts a
                                    // mode whose whole purpose is acting on a set.
                                    .contextMenu(menuItems: {
                                        if !isSelecting {
                                            Button("Delete") {
                                                pendingDelete = .single(video)
                                            }
                                        }
                                    })
                            }
                        }
                        .padding(gridSpacing)
                    }
                }

                if isSelecting {
                    selectionActionBar
                } else {
                    // Persistent disclaimer footer
                    Text("Photos and videos may be lost due to bugs or device issues. Back up important footage.")
                        .font(.system(size: 10))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .background(footerBackground)
                }
            }
        }
        .onAppear {
            loadVideos()
            // Drops anything that has already fired, so the badge count and
            // the list reflect what's genuinely still pending.
            scheduleStore.refresh()
        }
        // Hop off the current update: @Published replays its value the moment
        // this view subscribes, which on a cold launch lands mid body evaluation.
        .onReceive(notificationRouter.$mediaToOpen.compactMap { $0 }) { fileName in
            DispatchQueue.main.async { openFromNotification(fileName) }
        }
        .sheet(item: $selectedVideo) { item in
            // Swipe left/right between items — the pager hosts the same
            // VideoPlayerView / PhotoDetailView per page, so Save/Share/Delete
            // still work exactly as before.
            MediaPagerView(items: videos, initialItem: item) { deletedItem in
                delete(deletedItem)
                selectedVideo = nil
            }
            .environmentObject(subscriptionManager)
            // Forces a fresh view identity per tapped item. Without this,
            // SwiftUI reuses this sheet's existing @State storage between
            // presentations and throws away MediaPagerView's
            // State(initialValue:), so the pager would open on whichever item
            // was viewed last instead of the one just tapped.
            .id(item.id)
        }
        .alert(item: $pendingDelete) { pending in
            Alert(
                title: Text(pending.title),
                message: Text("This cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    switch pending {
                    case .single(let video):
                        delete(video)
                    case .batch(let items):
                        // Captured when the alert was raised, not re-read from
                        // selection now: the set could in principle have moved
                        // on, and the confirmation named a specific count.
                        items.forEach(delete)
                        selectedIDs.removeAll()
                        isSelecting = false
                    }
                },
                secondaryButton: .cancel()
            )
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView().environmentObject(subscriptionManager)
        }
        .modifier(TabBarHidden(hidden: isSelecting))
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var background: some View {
        if let flatBackground = appTheme.galleryBackground {
            // Flat theme's own ground colour — plain black for most, Matcha's
            // theme green for Matcha, where it stands in for the thumbnail
            // border that theme deliberately goes without.
            flatBackground.ignoresSafeArea()
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

    private var header: some View {
        HStack {
            if isSelecting {
                // The count replaces the title, so the thing most likely to be
                // checked before tapping Delete is the most prominent text.
                // One key, unlike the "%lld item/items" pair below: "Selected"
                // reads the same for one or many, so a plural split would be
                // two identical strings for translators to keep in sync.
                Text("\(selectedIDs.count) Selected")
                    .font(isFlatTheme ? .system(size: 20, weight: .heavy, design: .monospaced)
                                      : .title2.bold())
                    .foregroundColor(.white)
            } else if isFlatTheme {
                Text("GALLERY")
                    .font(.system(size: 22, weight: .heavy, design: .monospaced))
                    .tracking(3)
                    .foregroundColor(.white)
            } else {
                Text("Gallery")
                    .font(.largeTitle.bold())
                    .foregroundColor(.lightGray)
            }
            Spacer()

            if isSelecting {
                headerChip(title: "Cancel") {
                    isSelecting = false
                    selectedIDs.removeAll()
                }
            } else {
                // Hidden with nothing to select, where it would only be a dead
                // control — the empty state already explains the situation.
                if !videos.isEmpty {
                    headerChip(title: "Select") { isSelecting = true }
                }
                // Only present when something is actually waiting — a permanently
                // visible button would be dead weight most of the time.
                if !scheduleStore.items.isEmpty {
                    scheduledBadge
                }
            }
            if !isSelecting {
                if !subscriptionManager.isUnlocked {
                    Button(action: { showPaywall = true }) {
                        HStack(spacing: 5) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 11))
                            Text("PREMIUM")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .tracking(1)
                        }
                        .foregroundColor(isFlatTheme ? accentColor : Color(white: 0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            ZStack {
                                RoundedRectangle(cornerRadius: isFlatTheme ? 4 : 6)
                                    .fill(isFlatTheme ? Color.black : Color(white: 0.2))
                                RoundedRectangle(cornerRadius: isFlatTheme ? 4 : 6)
                                    .stroke(isFlatTheme ? accentColor : Color(white: 0.45),
                                            lineWidth: isFlatTheme ? 2 : 1)
                            }
                        )
                    }
                } else {
                    // Two full literal keys ("%lld item" / "%lld items") rather
                    // than a nested interpolation building the "s" suffix in
                    // code — the catalog can then hold a properly pluralized
                    // translation per language instead of an English-only rule
                    // baked into the source.
                    Text(videos.count == 1 ? "\(videos.count) item" : "\(videos.count) items")
                        .font(isFlatTheme ? .system(size: 12, weight: .bold, design: .monospaced) : .subheadline)
                        .foregroundColor(.white)
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 16)
        .padding(.bottom, 10)
        // Attached here rather than on the root ZStack: that already carries
        // the viewer and paywall sheets, and stacking a third on one view is
        // where SwiftUI starts dropping presentations.
        .sheet(isPresented: $showScheduledList) {
            ScheduledListSheet(store: scheduleStore)
        }
    }

    /// Small pill used by Select and Cancel, matching the visual weight of the
    /// Premium and scheduled badges it sits beside.
    private func headerChip(title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundColor(isFlatTheme ? accentColor : Color(white: 0.85))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: isFlatTheme ? 4 : 6)
                            .fill(isFlatTheme ? Color.black : Color(white: 0.2))
                        RoundedRectangle(cornerRadius: isFlatTheme ? 4 : 6)
                            .stroke(isFlatTheme ? accentColor : Color(white: 0.45),
                                    lineWidth: isFlatTheme ? 2 : 1)
                    }
                )
        }
        .padding(.trailing, 8)
    }

    /// Dims unselected thumbnails rather than only marking selected ones, so
    /// what is included reads at a glance across a full grid.
    @ViewBuilder
    private func selectionOverlay(for item: VideoItem) -> some View {
        if isSelecting {
            let isOn = selectedIDs.contains(item.id)
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color.black.opacity(isOn ? 0 : 0.45))

                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(isOn ? accentColor : Color.white.opacity(0.85))
                    // Solid backing so the glyph stays legible over bright
                    // footage, which a plain white circle does not.
                    .background(Circle().fill(Color.black.opacity(0.5)).frame(width: 26, height: 26))
                    .padding(8)
            }
            .allowsHitTesting(false)
        }
    }

    /// Share and Delete, shown in place of the disclaimer footer while
    /// selecting. Sits where the tab bar was, which is hidden on iOS 16+.
    private var selectionActionBar: some View {
        HStack(spacing: 0) {
            selectionAction(icon: "square.and.arrow.up", title: "Share",
                            tint: isFlatTheme ? accentColor : .lightGray) {
                // Matches the single item viewers, where Share is premium and
                // Delete is not — batch shouldn't be a way around that.
                if subscriptionManager.isUnlocked { shareSelected() }
                else { showPaywall = true }
            }
            selectionAction(icon: "trash", title: "Delete", tint: .red) {
                // Snapshot the selection into the alert itself. The alert is
                // owned by the root view (see pendingDelete), so nothing here
                // needs its own presentation modifier.
                pendingDelete = .batch(selectedItems)
            }
        }
        .padding(.vertical, 10)
        .background(Color(white: 0.08))
    }

    private func selectionAction(icon: String, title: LocalizedStringKey,
                                 tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
            }
            .foregroundColor(selectedIDs.isEmpty ? Color(white: 0.3) : tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        // Nothing selected means nothing to act on; leaving these live would
        // present a share sheet with no contents.
        .disabled(selectedIDs.isEmpty)
    }

    /// Shortcut into the alarm/reminder list, with a count so it's obvious how
    /// many are pending.
    private var scheduledBadge: some View {
        Button(action: { showScheduledList = true }) {
            HStack(spacing: 5) {
                Image(systemName: "alarm.fill")
                    .font(.system(size: 11))
                Text("\(scheduleStore.items.count)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
            }
            .foregroundColor(isFlatTheme ? accentColor : Color(white: 0.85))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: isFlatTheme ? 4 : 6)
                        .fill(isFlatTheme ? Color.black : Color(white: 0.2))
                    RoundedRectangle(cornerRadius: isFlatTheme ? 4 : 6)
                        .stroke(isFlatTheme ? accentColor : Color(white: 0.45),
                                lineWidth: isFlatTheme ? 2 : 1)
                }
            )
        }
        .padding(.trailing, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            if isFlatTheme {
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(accentColor, lineWidth: 2)
                        .frame(width: 90, height: 90)
                    Image(systemName: "rectangle.stack.fill")
                        .font(.system(size: 34))
                        .foregroundColor(accentColor)
                }
            } else {
                Image(systemName: "film.stack")
                    .font(.system(size: 60))
                    .foregroundColor(Color(white: 0.35))
            }
            Text("No photos or videos yet")
                .font(isFlatTheme ? .system(size: 14, weight: .bold, design: .monospaced) : .title3)
                .foregroundColor(isFlatTheme ? Color(white: 0.6) : Color(white: 0.45))
            Spacer()
        }
    }

    @ViewBuilder
    private var footerBackground: some View {
        if isFlatTheme {
            // No fill: the disclaimer just sits directly on the gallery's own
            // background across every theme, rather than on a distinct bar.
            // The thin accent line on top is a divider, not a background.
            Rectangle().fill(accentColor).frame(height: 1).frame(maxHeight: .infinity, alignment: .top)
        } else {
            Color.clear
        }
    }

    // MARK: - Data

    /// Reads the gallery straight off disk. Static and returning a value —
    /// rather than assigning `videos` — so a notification tap can resolve an
    /// item on a cold launch without waiting for the @State write to land.
    private static func currentItems() -> [VideoItem] {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: docs,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        return files
            .filter { ["mov", "mp4", "jpg", "jpeg", "png"].contains($0.pathExtension.lowercased()) }
            .sorted {
                let d1 = (try? $0.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                let d2 = (try? $1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                // Swift's sort isn't stable, so equal timestamps could come back
                // in a different order on each reload and shuffle the grid.
                // Filenames carry the capture time, so they break ties in the
                // same order and keep the listing deterministic.
                if d1 != d2 { return d1 > d2 }
                return $0.lastPathComponent > $1.lastPathComponent
            }
            .map { VideoItem(url: $0) }
    }

    private func loadVideos() {
        videos = Self.currentItems()
    }

    /// Opens the item behind a tapped alarm or reminder. Resolved by filename
    /// rather than by URL, because the app's container path changes between
    /// launches and updates — a stored absolute URL would silently stop
    /// matching after any app update.
    private func openFromNotification(_ fileName: String) {
        notificationRouter.mediaToOpen = nil

        let items = videos.isEmpty ? Self.currentItems() : videos
        if videos.isEmpty { videos = items }

        guard let match = items.first(where: { $0.url.lastPathComponent == fileName }) else { return }
        selectedVideo = match
    }

    // MARK: - Selection

    private func toggleSelection(_ item: VideoItem) {
        if selectedIDs.contains(item.id) {
            selectedIDs.remove(item.id)
        } else {
            selectedIDs.insert(item.id)
        }
    }

    /// Selected items in the order they appear in the grid, not the arbitrary
    /// order of a Set, so what gets shared or deleted matches what was seen.
    private var selectedItems: [VideoItem] {
        videos.filter { selectedIDs.contains($0.id) }
    }

    private func shareSelected() {
        let urls = selectedItems.map { $0.url }
        guard !urls.isEmpty else { return }

        // File URLs, not loaded media — the count barely affects memory, so
        // there is no reason to cap it. What actually limits a large share is
        // total bytes and whatever the chosen destination will accept.
        let activityVC = UIActivityViewController(activityItems: urls, applicationActivities: nil)

        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }

        // Required on iPad, where a share sheet is a popover and presenting one
        // without an anchor raises rather than falling back to a sheet. This
        // app supports iPad orientations, so it is genuinely reachable.
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX,
                                        y: top.view.bounds.maxY - 60,
                                        width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        activityVC.completionWithItemsHandler = { _, completed, _, _ in
            // Only leave selection mode once something actually happened;
            // dismissing the sheet to reconsider shouldn't discard the set.
            if completed {
                selectedIDs.removeAll()
                isSelecting = false
            }
        }
        top.present(activityVC, animated: true)
    }

    private func delete(_ video: VideoItem) {
        try? FileManager.default.removeItem(at: video.url)
        videos.removeAll { $0.id == video.id }
        // Any alarm/reminder pointing here would now fire and land on nothing.
        ScheduleStore.shared.removeAll(forFileName: video.url.lastPathComponent)
    }
}

/// Hides the tab bar while multi-select is active, matching the native
/// gallery, where the action bar takes over the bottom of the screen.
///
/// The API for this is iOS 16 and up; this app deploys to 14. Below that
/// there is no supported way for a view inside a TabView to hide its bar, so
/// it stays put and the action bar sits above it — visually less clean, but
/// fully functional, and no user is blocked from anything.
///
/// The availability check reads as two branches, which normally risks
/// changing view identity — harmless here because the OS version cannot
/// change while the app is running, so a given install only ever takes one.
private struct TabBarHidden: ViewModifier {
    let hidden: Bool

    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.toolbar(hidden ? .hidden : .visible, for: .tabBar)
        } else {
            content
        }
    }
}

/// What a pending delete confirmation refers to.
///
/// Carries the items themselves rather than just a count, so the alert acts
/// on exactly the set that was on screen when it was raised, and so a single
/// `.alert(item:)` on the root can serve both the long-press delete and the
/// multi-select one. Two `.alert(isPresented:)` modifiers in one hierarchy do
/// not both work — the descendant's is silently ignored.
private enum PendingDelete: Identifiable {
    case single(VideoItem)
    case batch([VideoItem])

    /// Distinct per presentation: SwiftUI only re-presents when the id
    /// changes, so batches of the same size must not collide.
    var id: String {
        switch self {
        case .single(let item):
            return "single-\(item.id.absoluteString)"
        case .batch(let items):
            return "batch-" + items.map { $0.id.absoluteString }.joined(separator: "|")
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .single:
            return "Delete video?"
        case .batch(let items):
            return items.count == 1 ? "Delete \(items.count) item?"
                                    : "Delete \(items.count) items?"
        }
    }
}
