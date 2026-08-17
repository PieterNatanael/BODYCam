import Foundation

struct VideoItem: Identifiable {
    let id: URL
    let url: URL

    init(url: URL) {
        self.id = url
        self.url = url
    }

    var isPhoto: Bool {
        ["jpg", "jpeg", "png"].contains(url.pathExtension.lowercased())
    }

    /// Human-readable label used in alarms, reminders and their list. The
    /// on-disk names ("video_1755183041.28.mov") aren't meaningful to anyone,
    /// so this leans on the capture date instead.
    var displayName: String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let date = attrs?[.creationDate] as? Date ?? Date()
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return (isPhoto ? "Photo · " : "Video · ") + f.string(from: date)
    }
}
