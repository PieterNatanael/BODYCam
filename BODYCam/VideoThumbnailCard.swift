import SwiftUI
import AVFoundation
import ImageIO

struct VideoThumbnailCard: View {
    let item: VideoItem

    @State private var thumbnail: UIImage?
    @State private var duration: String = ""
    @State private var date: String = ""

    @AppStorage("AppTheme") private var appThemeRaw: String = AppTheme.tropical.rawValue
    private var appTheme: AppTheme { AppTheme(rawValue: appThemeRaw) ?? .normal }
    private var isFlatTheme: Bool { appTheme.isFlat }
    private var accentColor: Color { appTheme.galleryAccent }
    @AppStorage("ShowThumbnailMetadata") private var showThumbnailMetadata: Bool = false

    /// Fixed cell height. Declared once and used for the frame so the drawn
    /// content and the layout box can never disagree.
    private static let cellHeight: CGFloat = 160

    /// Shared across every card, keyed by file URL. Scrolling far down a
    /// long gallery and back up can recreate cells that had already
    /// appeared once — LazyVGrid doesn't keep unlimited off screen views
    /// alive forever — and without this, that redid the full decode/
    /// generate work from scratch every time, which is exactly the kind of
    /// repeated, avoidable cost that reads as scroll jank. NSCache evicts
    /// on its own under memory pressure, so this never needs manual
    /// clearing; countLimit is just a sane ceiling, not a tuned budget.
    private static let thumbnailCache: NSCache<NSURL, UIImage> = {
        let cache = NSCache<NSURL, UIImage>()
        cache.countLimit = 500
        return cache
    }()

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
                // Duration badge, bottom trailing, videos only — matches the
                // native Photos app: no separate photo/video type icon is
                // needed once only videos carry a duration at all, so the
                // badge itself already tells them apart. Always visible,
                // independent of showThumbnailMetadata, which is a
                // separate, richer info bar rather than a replacement for
                // this at-a-glance one.
                .overlay(durationBadge, alignment: .bottomTrailing)

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

    /// Empty for photos, and for a video whose duration hasn't loaded yet —
    /// @ViewBuilder's if with no else renders nothing in either case, rather
    /// than an empty badge box briefly flashing before the real value lands.
    @ViewBuilder
    private var durationBadge: some View {
        if !item.isPhoto, !duration.isEmpty {
            Text(duration)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.6))
                .cornerRadius(4)
                .padding(6)
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

        if let cached = Self.thumbnailCache.object(forKey: url as NSURL) {
            thumbnail = cached
            return
        }

        if item.isPhoto {
            DispatchQueue.global(qos: .userInitiated).async {
                guard let image = Self.downsampledImage(at: url, maxPixelSize: Self.cellHeight * 3) else { return }
                Self.thumbnailCache.setObject(image, forKey: url as NSURL)
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
                Self.thumbnailCache.setObject(image, forKey: url as NSURL)
                DispatchQueue.main.async { thumbnail = image }
            }
        }
    }

    /// Decodes directly at thumbnail size via ImageIO rather than loading the
    /// full image and letting SwiftUI's .resizable()/.scaledToFill() shrink
    /// it visually afterward — that still means fully decoding the source
    /// pixel data first. For a Max quality photo (up to the device's true
    /// sensor resolution), that is tens of megabytes of decoded bitmap for
    /// something displayed at under 200 points tall; multiplied across a
    /// scrolling grid, that repeated decode cost is exactly the kind of
    /// thing that reads as jank. CGImageSourceCreateThumbnailAtIndex decodes
    /// straight to the requested pixel size instead of decoding-then-scaling.
    private static func downsampledImage(at url: URL, maxPixelSize: CGFloat) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            // Bakes in any EXIF rotation so the thumbnail's pixels are
            // already upright, matching what displaying the full image would
            // show — a no-op for this app's own captures, whose orientation
            // is already baked into the pixels rather than tagged, but
            // correct regardless of how a file ended up on disk.
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
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
