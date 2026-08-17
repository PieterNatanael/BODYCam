import SwiftUI
import AVFoundation

struct VideoThumbnailCard: View {
    let item: VideoItem

    @State private var thumbnail: UIImage?
    @State private var duration: String = ""
    @State private var date: String = ""

    @AppStorage("AppTheme") private var appThemeRaw: String = AppTheme.simple.rawValue
    private var appTheme: AppTheme { AppTheme(rawValue: appThemeRaw) ?? .normal }
    private var isFlatTheme: Bool { appTheme.isFlat }
    private var accentColor: Color { appTheme.galleryAccent }

    var body: some View {
        // GeometryReader forces an EXPLICIT, concrete width/height (matching
        // exactly what the grid column proposes) rather than relying on
        // .frame(maxWidth: .infinity) to cap things. scaledToFill's aspect-
        // ratio-driven intrinsic sizing could still leak a wide (landscape)
        // source image's natural width through a maxWidth-based frame,
        // ballooning the card past its column — geo.size leaves no ambiguity
        // for that to hide in.
        GeometryReader { geo in
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
                                Image(systemName: item.isPhoto ? "photo.fill" : "video.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(isFlatTheme ? accentColor : Color(white: 0.35))
                            )
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .cornerRadius(isFlatTheme ? 0 : 8)
                .overlay(
                    RoundedRectangle(cornerRadius: isFlatTheme ? 0 : 8)
                        .stroke(isFlatTheme ? accentColor : Color.clear, lineWidth: isFlatTheme ? 2 : 0)
                )
                // Small media-type badge, top-trailing, so photos and videos are
                // distinguishable at a glance in the mixed grid.
                .overlay(
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: item.isPhoto ? "photo.fill" : "video.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(5)
                                .background(Color.black.opacity(0.55))
                                .clipShape(Circle())
                                .padding(6)
                        }
                        Spacer()
                    }
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
                    .frame(width: geo.size.width, height: geo.size.height)
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
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(height: 160)
        .onAppear {
            loadThumbnail()
            loadMetadata()
        }
        // onAppear alone is not enough. Adding new recordings shifts every
        // existing cell down the grid, and SwiftUI reuses those cell views with
        // a different `item` rather than rebuilding them — but @State survives
        // that reuse, so the cell carried on showing the PREVIOUS item's
        // thumbnail while its tap handler already pointed at the new one. That
        // is what made tapping a cell open something else.
        .onChange(of: item.id) { _ in
            // Cleared first so the old image can't linger during the async load.
            thumbnail = nil
            duration = ""
            date = ""
            loadThumbnail()
            loadMetadata()
        }
    }

    // MARK: - Loaders

    private func loadThumbnail() {
        let url = item.url
        if item.isPhoto {
            DispatchQueue.global(qos: .userInitiated).async {
                guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return }
                DispatchQueue.main.async { thumbnail = image }
            }
            return
        }
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
        let isPhoto = item.isPhoto
        DispatchQueue.global(qos: .userInitiated).async {
            let durationStr: String
            if isPhoto {
                durationStr = ""
            } else {
                let asset = AVAsset(url: url)
                let secs = CMTimeGetSeconds(asset.duration)
                durationStr = secs.isNaN ? "" : String(format: "%d:%02d", Int(secs) / 60, Int(secs) % 60)
            }

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
