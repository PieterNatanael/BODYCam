import SwiftUI
import AVFoundation

struct RootView: View {
    @StateObject private var subscriptionManager = SubscriptionManager()
    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(white: 0.09, alpha: 1)

        let normal = appearance.stackedLayoutAppearance.normal
        normal.iconColor = UIColor(white: 0.55, alpha: 1)
        normal.titleTextAttributes = [.foregroundColor: UIColor(white: 0.55, alpha: 1)]

        let selected = appearance.stackedLayoutAppearance.selected
        selected.iconColor = UIColor(white: 0.0, alpha: 1)
        selected.titleTextAttributes = [.foregroundColor: UIColor(white: 0.0, alpha: 1)]

        UITabBar.appearance().standardAppearance = appearance
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
        UITabBar.appearance().tintColor = UIColor(white: 0.25, alpha: 1)
        UITabBar.appearance().unselectedItemTintColor = UIColor(white: 0.55, alpha: 1)
    }

    @State private var showDisclaimer = !UserDefaults.standard.bool(forKey: "hasSeenDisclaimer")
    @State private var isScreenDimmed = false
    @State private var wakeHintBlink  = false
    @State private var selectedTab    = 0
    @ObservedObject private var notificationRouter = NotificationRouter.shared

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                ContentView()
                    .environmentObject(subscriptionManager)
                    .tabItem {
                        Label("Video", systemImage: "video.fill")
                    }
                    .tag(0)
                PhotoCameraView()
                    .environmentObject(subscriptionManager)
                    .tabItem {
                        Label("Photo", systemImage: "camera.fill")
                    }
                    .tag(1)
                GalleryView()
                    .environmentObject(subscriptionManager)
                    .tabItem {
                        Label("Gallery", systemImage: "film.stack")
                    }
                    .tag(2)
            }
            .onAppear { subscriptionManager.start() }
            // A tapped alarm/reminder names a photo or video — switch to the
            // Gallery tab so GalleryView (which owns the item list) can open it.
            .onReceive(notificationRouter.$mediaToOpen.compactMap { $0 }) { _ in
                selectedTab = 2
            }

            // Full-screen screen-off overlay — covers tab bar so iOS's adaptive
            // "go white on low brightness" behaviour is completely hidden
            if isScreenDimmed {
                ZStack {
                    Color.black.ignoresSafeArea()

                    VStack {
                        Spacer()
                        VStack(spacing: 10) {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 5, height: 5)
                                .opacity(wakeHintBlink ? 0.18 : 0.05)
                                .animation(
                                    Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                                    value: wakeHintBlink
                                )
                            Text("·  T A P  T O  W A K E  ·")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.white)
                                .opacity(0.08)
                        }
                        .padding(.bottom, 70)
                    }
                }
                .onTapGesture {
                    // Tell ContentView to restore brightness — it will then post
                    // .screenDidWake back so we hide the overlay (one-way, no loop)
                    NotificationCenter.default.post(name: .userRequestedWake, object: nil)
                }
                .onAppear  { wakeHintBlink = true  }
                .onDisappear { wakeHintBlink = false }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .screenDidDim)) { _ in
            isScreenDimmed = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .screenDidWake)) { _ in
            isScreenDimmed = false
            // iOS overrides tab bar colours to white when brightness drops to ~0.
            // Directly update the live UITabBar instance so colours snap back.
            repinTabBarColors()
        }
        .fullScreenCover(isPresented: $showDisclaimer) {
            DisclaimerView {
                UserDefaults.standard.set(true, forKey: "hasSeenDisclaimer")
                showDisclaimer = false
            }
        }
    }

    // MARK: - Tab bar colour restoration

    /// Walk the window's view hierarchy to find the live UITabBar and force its
    /// colours back, overriding whatever iOS set while brightness was at minimum.
    private func repinTabBarColors() {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow })
                        ?? windowScene.windows.first
        else { return }

        for tabBar in findTabBars(in: window) {
            tabBar.tintColor = UIColor(white: 0.25, alpha: 1)
            tabBar.unselectedItemTintColor = UIColor(white: 0.55, alpha: 1)
        }
    }

    private func findTabBars(in view: UIView) -> [UITabBar] {
        var found: [UITabBar] = []
        if let tb = view as? UITabBar { found.append(tb) }
        for sub in view.subviews { found += findTabBars(in: sub) }
        return found
    }
}
