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

    /// 0 if the file can't be read rather than throwing — used only for the
    /// Gallery's total storage figure, where one unreadable file shouldn't
    /// break the whole count.
    var fileSizeBytes: Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        // NSNumber, not Int64 directly — attributesOfItem's dictionary is
        // [FileAttributeKey: Any], and .size bridges through as NSNumber.
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
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
