import SwiftUI

struct GalleryView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @State private var videos: [VideoItem] = []
    @State private var selectedVideo: VideoItem?
    @State private var videoToDelete: VideoItem?
    @State private var showDeleteAlert = false
    @State private var showPaywall = false
    @AppStorage("AppTheme") private var appThemeRaw: String = AppTheme.normal.rawValue
    private var appTheme: AppTheme { AppTheme(rawValue: appThemeRaw) ?? .normal }
    private var isFlatTheme: Bool { appTheme != .normal }
    private let simpleRed = Color(red: 0.85, green: 0.15, blue: 0.1)
    private let tacticalGreen = Color(red: 0.25, green: 0.95, blue: 0.4)
    private var accentColor: Color { appTheme == .tactical ? tacticalGreen : simpleRed }

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
                Text("Recordings may be lost due to bugs or device issues. Back up important footage.")
                    .font(.system(size: 10))
                    .foregroundColor(isFlatTheme ? Color(white: 0.5) : Color(white: 0.35))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(footerBackground)
            }
        }
        .onAppear(perform: loadVideos)
        .sheet(item: $selectedVideo) { video in
            VideoPlayerView(item: video) {
                delete(video)
                selectedVideo = nil
            }
            .environmentObject(subscriptionManager)
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
        if isFlatTheme {
            // Bauhaus: flat, no texture, no gradient.
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
                Text("\(videos.count) video\(videos.count == 1 ? "" : "s")")
                    .font(isFlatTheme ? .system(size: 12, weight: .bold, design: .monospaced) : .subheadline)
                    .foregroundColor(isFlatTheme ? Color(white: 0.6) : Color(white: 0.5))
            }
        }
        .padding(.horizontal)
        .padding(.top, 16)
        .padding(.bottom, 10)
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
            Text("No recordings yet")
                .font(isFlatTheme ? .system(size: 14, weight: .bold, design: .monospaced) : .title3)
                .foregroundColor(isFlatTheme ? Color(white: 0.6) : Color(white: 0.45))
            Spacer()
        }
    }

    @ViewBuilder
    private var footerBackground: some View {
        if isFlatTheme {
            VStack(spacing: 0) {
                Rectangle().fill(accentColor).frame(height: 1)
                Color.black
            }
        } else {
            Color.black.opacity(0.4)
        }
    }

    // MARK: - Data

    private func loadVideos() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: docs,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return }

        videos = files
            .filter { ["mov", "mp4"].contains($0.pathExtension.lowercased()) }
            .sorted {
                let d1 = (try? $0.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                let d2 = (try? $1.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                return d1 > d2
            }
            .map { VideoItem(url: $0) }
    }

    private func delete(_ video: VideoItem) {
        try? FileManager.default.removeItem(at: video.url)
        videos.removeAll { $0.id == video.id }
    }
}
