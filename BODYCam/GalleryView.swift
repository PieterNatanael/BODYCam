import SwiftUI

struct GalleryView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @State private var videos: [VideoItem] = []
    @State private var selectedVideo: VideoItem?
    @State private var videoToDelete: VideoItem?
    @State private var showDeleteAlert = false
    @State private var showPaywall = false
    @ObservedObject private var notificationRouter = NotificationRouter.shared
    @ObservedObject private var scheduleStore = ScheduleStore.shared
    @State private var showScheduledList = false
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
                                    .onTapGesture { selectedVideo = video }
                                    .contextMenu {
                                        Button("Delete") {
                                            videoToDelete = video
                                            showDeleteAlert = true
                                        }
                                    }
                            }
                        }
                        .padding(gridSpacing)
                    }
                }

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
        .alert(isPresented: $showDeleteAlert) {
            Alert(
                title: Text("Delete video?"),
                message: Text("This cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    if let v = videoToDelete { delete(v) }
                },
                secondaryButton: .cancel()
            )
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView().environmentObject(subscriptionManager)
        }
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
            if isFlatTheme {
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
            // Only present when something is actually waiting — a permanently
            // visible button would be dead weight most of the time.
            if !scheduleStore.items.isEmpty {
                scheduledBadge
            }
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
                Text("\(videos.count) item\(videos.count == 1 ? "" : "s")")
                    .font(isFlatTheme ? .system(size: 12, weight: .bold, design: .monospaced) : .subheadline)
                    .foregroundColor(.white)
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

    private func delete(_ video: VideoItem) {
        try? FileManager.default.removeItem(at: video.url)
        videos.removeAll { $0.id == video.id }
        // Any alarm/reminder pointing here would now fire and land on nothing.
        ScheduleStore.shared.removeAll(forFileName: video.url.lastPathComponent)
    }
}
