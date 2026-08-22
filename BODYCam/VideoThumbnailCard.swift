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
    @AppStorage("ShowThumbnailMetadata") private var showThumbnailMetadata: Bool = false

    /// Fixed cell height. Declared once and used for the frame so the drawn
    /// content and the layout box can never disagree.
    private static let cellHeight: CGFloat = 160

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Color.clear accepts the frame exactly, and overlay content can
            // never influence its parent's size — so a wide landscape
            // thumbnail is cropped rather than stretching the cell.
            //
            // This replaces a GeometryReader, which allowed the cell's layout
            // box and its drawn content to disagree: the visible artwork sat
            // lower than the box the grid actually reserved, so a tap near the
            // bottom of a cell landed on the row beneath it. In a two column
            // grid that neighbour is index + 2, which is exactly why tapping
            // the first item opened the third.
            Color.clear
                .frame(maxWidth: .infinity, minHeight: Self.cellHeight, maxHeight: Self.cellHeight)
                .overlay(thumbnailContent)
                .clipped()
                .cornerRadius(isFlatTheme ? 0 : 8)
                // Media type badge, top trailing, so photos and videos are
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

            if showThumbnailMetadata {
                metadataPlate
            }
        }
        .frame(maxWidth: .infinity, minHeight: Self.cellHeight, maxHeight: Self.cellHeight)
        // Pins the tappable region to exactly the cell box, rather than letting
        // hit testing follow whatever happens to be drawn.
        .contentShape(Rectangle())
        .onAppear {
            loadThumbnail()
            loadMetadata()
        }
        // onAppear alone is not enough. Adding new recordings shifts every
        // existing cell down the grid, and SwiftUI reuses those cell views with
        // a different `item` rather than rebuilding them — but @State survives
        // that reuse, so the cell carried on showing the PREVIOUS item's
        // thumbnail while its tap handler already pointed at the new one.
        .onChange(of: item.id) { _ in
            // Cleared first so the old image can't linger during the async load.
            thumbnail = nil
            duration = ""
            date = ""
            loadThumbnail()
            loadMetadata()
        }
    }

    @ViewBuilder
    private var thumbnailContent: some View {
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

    /// Duration and date: a flat full width plate in the flat themes, a floating
    /// translucent pill in Normal.
    @ViewBuilder
    private var metadataPlate: some View {
        if isFlatTheme {
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
