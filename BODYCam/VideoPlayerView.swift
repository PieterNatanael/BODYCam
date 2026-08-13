import SwiftUI
import AVKit
import Photos
import Combine

struct VideoPlayerView: View {
    let item: VideoItem
    var onDelete: () -> Void

    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.presentationMode) private var presentationMode

    @State private var player: AVPlayer?
    @State private var showDeleteAlert = false
    @State private var showPaywall     = false
    @State private var saveStatus: SaveStatus?

    /// Fires every 0.25 s to enforce the 15-second preview cap.
    /// Only active while the view is visible — cancelled in .onDisappear.
    private let previewTimer = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    private static let previewLimit: Double = 15

    enum SaveStatus { case saving, success, failure }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                playerArea
                if !subscriptionManager.isUnlocked {
                    previewBanner
                }
                actionBar
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView().environmentObject(subscriptionManager)
        }
        .onAppear {
            player = AVPlayer(url: item.url)
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
        // Enforce 15-second preview for free users
        .onReceive(previewTimer) { _ in
            guard !subscriptionManager.isUnlocked,
                  let player = player,
                  !showPaywall else { return }

            let seconds = player.currentTime().seconds
            guard seconds.isFinite, seconds >= Self.previewLimit else { return }

            player.pause()
            player.seek(to: CMTime(seconds: Self.previewLimit,
                                   preferredTimescale: 600))
            showPaywall = true
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
                    .foregroundColor(Color(white: 0.6))
            }
            Spacer()
            Text(formattedDate)
                .font(.caption)
                .foregroundColor(Color(white: 0.5))
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    private var playerArea: some View {
        Group {
            if let player {
                VideoPlayer(player: player)
            }
        }
    }

    /// Shown below the player for free-tier users.
    private var previewBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 11))
            Text("FREE PREVIEW — first 15 seconds only")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
        }
        .foregroundColor(Color(white: 0.5))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(Color(white: 0.07))
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
                color: .lightGray,
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

    private func actionButton(icon: String, label: String,
                               color: Color, locked: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.system(size: 22))
                    if locked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 9))
                            .foregroundColor(Color(white: 0.55))
                            .offset(x: 6, y: -4)
                    }
                }
                Text(label)
                    .font(.caption)
            }
            .foregroundColor(locked ? Color(white: 0.38) : color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
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

    private var saveLabel: String {
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
        default:       return .lightGray
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
        top.present(activityVC, animated: true)
    }
}
