import SwiftUI
import Photos

struct PhotoDetailView: View {
    let item: VideoItem
    var onDelete: () -> Void

    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.presentationMode) private var presentationMode

    @State private var image: UIImage?
    @State private var showDeleteAlert = false
    @State private var showPaywall     = false
    @State private var saveStatus: SaveStatus?
    @State private var scheduleMode: ScheduleMode?

    enum SaveStatus { case saving, success, failure }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                imageArea
                actionBar
            }
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView().environmentObject(subscriptionManager)
        }
        .sheet(item: $scheduleMode) { mode in
            ScheduleSheet(item: item, mode: mode) {}
        }
        .onAppear(perform: loadImage)
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
                    .foregroundColor(Color(white: 0.6))
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
                .foregroundColor(Color(white: 0.6))
                .padding(.leading, 12)
        }
    }

    private var imageArea: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        top.present(activityVC, animated: true)
    }
}
