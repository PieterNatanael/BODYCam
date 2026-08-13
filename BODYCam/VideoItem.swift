import Foundation

struct VideoItem: Identifiable {
    let id: URL
    let url: URL

    init(url: URL) {
        self.id = url
        self.url = url
    }
}
