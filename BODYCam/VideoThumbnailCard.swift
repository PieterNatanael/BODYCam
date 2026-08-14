import SwiftUI
import AVFoundation

struct VideoThumbnailCard: View {
    let item: VideoItem

    @State private var thumbnail: UIImage?
    @State private var duration: String = ""
    @State private var date: String = ""

    @AppStorage("AppTheme") private var appThemeRaw: String = AppTheme.normal.rawValue
    private var appTheme: AppTheme { AppTheme(rawValue: appThemeRaw) ?? .normal }
    private var isFlatTheme: Bool { appTheme != .normal }
    private let simpleRed = Color(red: 0.85, green: 0.15, blue: 0.1)
    private let tacticalGreen = Color(red: 0.25, green: 0.95, blue: 0.4)
    private var accentColor: Color { appTheme == .tactical ? tacticalGreen : simpleRed }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Thumbnail or placeholder
            Group {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(Color(white: 0.12))
                        .overlay(
                            Image(systemName: "video.fill")
                                .font(.system(size: 28))
                                .foregroundColor(isFlatTheme ? accentColor : Color(white: 0.35))
                        )
                }
            }
            .frame(height: 160)
            .clipped()
            .cornerRadius(isFlatTheme ? 0 : 8)
            .overlay(
                RoundedRectangle(cornerRadius: isFlatTheme ? 0 : 8)
                    .stroke(isFlatTheme ? accentColor : Color.clear, lineWidth: isFlatTheme ? 2 : 0)
            )

            // Duration + date overlay: flat full-width label plate in Simple/
            // Tactical theme, floating translucent pill in Normal theme.
            if isFlatTheme {
                VStack {
                    Spacer()
                    HStack {
                        if !duration.isEmpty {
                            Text(duration)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.white)
                        }
                        Spacer()
                        if !date.isEmpty {
                            Text(date)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(Color(white: 0.7))
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.black)
                }
                .frame(height: 160)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    if !duration.isEmpty {
                        Text(duration)
                            .font(.caption.bold())
                            .foregroundColor(.white)
                    }
                    if !date.isEmpty {
                        Text(date)
                            .font(.caption2)
                            .foregroundColor(Color(white: 0.75))
                    }
                }
                .padding(6)
                .background(Color.black.opacity(0.55))
                .cornerRadius(6)
                .padding(6)
            }
        }
        .onAppear {
            loadThumbnail()
            loadMetadata()
        }
    }

    // MARK: - Loaders

    private func loadThumbnail() {
        let url = item.url
        DispatchQueue.global(qos: .userInitiated).async {
            let asset = AVAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 400, height: 400)
            let time = CMTimeMake(value: 0, timescale: 60)
            generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cgImage, _, _, _ in
                guard let cgImage else { return }
                let image = UIImage(cgImage: cgImage)
                DispatchQueue.main.async { thumbnail = image }
            }
        }
    }

    private func loadMetadata() {
        let url = item.url
        DispatchQueue.global(qos: .userInitiated).async {
            let asset = AVAsset(url: url)
            let secs = CMTimeGetSeconds(asset.duration)
            let durationStr = secs.isNaN ? "" : String(format: "%d:%02d", Int(secs) / 60, Int(secs) % 60)

            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let fileDate = attrs?[.creationDate] as? Date ?? Date()
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            let dateStr = formatter.string(from: fileDate)

            DispatchQueue.main.async {
                duration = durationStr
                date = dateStr
            }
        }
    }
}
