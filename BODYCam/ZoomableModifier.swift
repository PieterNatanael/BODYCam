import SwiftUI

/// Pinch to zoom, drag to pan once zoomed, and double tap to jump between 1x
/// and a fixed zoomed level — the same three gestures the native gallery uses
/// on a single photo or video frame.
///
/// Always used inside MediaPagerView's paging TabView, which is what shapes
/// two of the choices here:
///   - The pan gesture's minimum recognition distance is swapped to a huge
///     number while at 1x, so an ordinary swipe can never satisfy it and the
///     TabView's own page swipe is left completely unimpeded. Only once
///     zoomed does the threshold drop to 0, at which point `.highPriorityGesture`
///     lets a pan win over paging so you can't accidentally flip to the next
///     item while trying to move around inside a zoomed one.
///   - Single tap and double tap are composed with `.exclusively(before:)`
///     rather than attached independently, so a double tap can't also fire
///     the single tap handler (used here to toggle each viewer's chrome) on
///     its first touch.
struct ZoomableModifier: ViewModifier {
    /// Runs on a genuine single tap, not the first half of a double tap.
    var onSingleTap: () -> Void = {}

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let minScale: CGFloat = 1
    private let maxScale: CGFloat = 5
    private let doubleTapScale: CGFloat = 2.5

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .offset(offset)
            .simultaneousGesture(magnification)
            .highPriorityGesture(pan)
            .simultaneousGesture(tap)
            .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.85), value: scale)
            .animation(.interactiveSpring(response: 0.35, dampingFraction: 0.85), value: offset)
    }

    private var magnification: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = min(max(lastScale * value, minScale), maxScale)
            }
            .onEnded { _ in
                lastScale = scale
                if scale <= minScale { resetOffset() } else { clampOffset() }
            }
    }

    private var pan: some Gesture {
        DragGesture(minimumDistance: scale > minScale ? 0 : 10_000)
            .onChanged { value in
                guard scale > minScale else { return }
                offset = CGSize(width: lastOffset.width + value.translation.width,
                                 height: lastOffset.height + value.translation.height)
            }
            .onEnded { _ in
                guard scale > minScale else { return }
                clampOffset()
            }
    }

    private var tap: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                if scale > minScale {
                    scale = minScale
                    resetOffset()
                } else {
                    scale = doubleTapScale
                    lastScale = doubleTapScale
                }
            }
            .exclusively(before: TapGesture(count: 1).onEnded(onSingleTap))
    }

    private func resetOffset() {
        offset = .zero
        lastOffset = .zero
    }

    /// Keeps a zoomed image or video from being dragged off screen entirely.
    /// Measured against the screen rather than this view's own frame — this
    /// modifier is only ever used on a full-screen viewer, so the two are
    /// effectively the same, without needing to thread a GeometryReader
    /// through every gesture callback.
    private func clampOffset() {
        let bounds = UIScreen.main.bounds.size
        let maxX = bounds.width  * (scale - 1) / 2
        let maxY = bounds.height * (scale - 1) / 2
        offset.width  = min(max(offset.width,  -maxX), maxX)
        offset.height = min(max(offset.height, -maxY), maxY)
        lastOffset = offset
    }
}

extension View {
    /// Pinch to zoom, drag to pan once zoomed, and double tap to jump between
    /// 1x and a fixed zoomed level. `onSingleTap` still fires for an ordinary
    /// single tap so callers can keep using it for things like a chrome
    /// toggle, without that tap also being consumed as half of a double tap.
    func zoomable(onSingleTap: @escaping () -> Void = {}) -> some View {
        modifier(ZoomableModifier(onSingleTap: onSingleTap))
    }
}
