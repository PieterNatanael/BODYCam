import SwiftUI

// Swipeable full-screen viewer over a mixed list of photos and videos —
// each page is the existing VideoPlayerView / PhotoDetailView (so Save/Share/
// Delete keep working exactly as before), just hosted inside a paging TabView
// instead of being presented one at a time.
struct MediaPagerView: View {
    let items: [VideoItem]
    let initialItem: VideoItem
    var onDelete: (VideoItem) -> Void

    @State private var currentID: URL

    // NOTE: State(initialValue:) is only honoured when SwiftUI creates fresh
    // state storage for this view. The presenting sheet in GalleryView carries
    // an .id(item.id) to guarantee that per tapped item — without it SwiftUI
    // reuses the previous presentation's storage, this initial value is
    // discarded, and the pager opens on the previously viewed item.
    init(items: [VideoItem], initialItem: VideoItem, onDelete: @escaping (VideoItem) -> Void) {
        self.items = items
        self.initialItem = initialItem
        self.onDelete = onDelete
        _currentID = State(initialValue: initialItem.id)
    }

    var body: some View {
        TabView(selection: $currentID) {
            ForEach(items) { item in
                Group {
                    if item.isPhoto {
                        // isActive so the chrome's one-shot auto-hide starts
                        // when the page is actually reached, not while it's
                        // still being built off screen as a neighbour.
                        PhotoDetailView(item: item,
                                        onDelete: { onDelete(item) },
                                        isActive: item.id == currentID)
                    } else {
                        // Only the visible page plays — paging TabView keeps
                        // neighbours alive, so without this their audio would
                        // all run at once.
                        VideoPlayerView(item: item,
                                        onDelete: { onDelete(item) },
                                        isActive: item.id == currentID)
                    }
                }
                .tag(item.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(Color.black.ignoresSafeArea())
        .ignoresSafeArea()
    }
}
