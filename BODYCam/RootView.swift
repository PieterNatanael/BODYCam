import SwiftUI
import AVFoundation

struct RootView: View {
    @StateObject private var subscriptionManager = SubscriptionManager()
    @AppStorage("AppTheme") private var appThemeRaw: String = AppTheme.tropical.rawValue
    private var appTheme: AppTheme { AppTheme(rawValue: appThemeRaw) ?? .normal }

    init() {
        // Read straight from UserDefaults: @AppStorage isn't available yet
        // inside init, and the appearance proxy has to be configured before the
        // TabView is built or the first render uses stock colours.
        let raw = UserDefaults.standard.string(forKey: "AppTheme") ?? AppTheme.tropical.rawValue
        Self.applyTabBarColors(for: AppTheme(rawValue: raw) ?? .normal)
    }

    // Deliberately a NEW key rather than reusing "hasSeenDisclaimer": this
    // screen now explains the app's permissions, which nobody who accepted the
    // old warnings-only disclaimer has ever been shown. Reusing the old key
    // would hide that from every existing user forever. The cost is one extra
    // full screen, once, after updating — dismissed with a single tap.
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "hasSeenOnboarding")
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
                        // The brand rather than the screen's function, so the
                        // app's own name is present in the UI. Spelled out as
                        // Label { Text(verbatim:) } rather than the shorthand
                        // Label("LBC", systemImage:) because that shorthand
                        // takes a LocalizedStringKey — Xcode would extract the
                        // brand name into the string catalog as if it were
                        // translatable prose, and a translator could
                        // legitimately "translate" it. The screen's own header
                        // still reads Gallery, translated, so the tab is
                        // branding while the heading remains wayfinding.
                        Label {
                            Text(verbatim: "LBC")
                        } icon: {
                            // square.stack.3d.up.fill, not film.stack: film.stack
                            // was only added in iOS 16 (SF Symbols 4), so on this
                            // app's iOS 14 minimum — e.g. a real iPhone 6S, capped
                            // at iOS 15 — the name doesn't exist yet and the icon
                            // silently renders as nothing.
                            Image(systemName: "square.stack.3d.up.fill")
                        }
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
                        // Fades in once and then holds, rather than pulsing
                        // forever. A repeatForever animation keeps the render
                        // loop awake and stops ProMotion displays dropping to
                        // their low refresh rate — a real cost, on a screen
                        // that exists precisely to save power, for a 5pt dot
                        // at barely-visible opacity. Note this has no bearing
                        // on the screen sleeping: that is governed solely by
                        // UIApplication.isIdleTimerDisabled.
                        VStack(spacing: 10) {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 5, height: 5)
                                .opacity(wakeHintBlink ? 0.18 : 0)
                            Text("·  T A P  T O  W A K E  ·")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(.white)
                                .opacity(wakeHintBlink ? 0.08 : 0)
                        }
                        .animation(.easeInOut(duration: 0.6), value: wakeHintBlink)
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
            Self.applyTabBarColors(for: appTheme)
        }
        // Appearance can be changed from the Settings sheet while this is on
        // screen. The appearance proxy alone only affects tab bars created
        // afterwards, so applyTabBarColors also repaints the live one.
        .onChange(of: appThemeRaw) { _ in
            Self.applyTabBarColors(for: appTheme)
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView {
                UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
                showOnboarding = false
            }
        }
        // Settings can clear the flag while this view is already alive, so the
        // reset has to be observed rather than only read once at init.
        .onReceive(NotificationCenter.default.publisher(for: .showOnboardingAgain)) { _ in
            showOnboarding = true
        }
    }

    // MARK: - Tab bar colours

    /// Paints the tab bar for a theme, via the appearance proxy AND any tab bar
    /// already on screen. Both are needed: the proxy only reaches instances
    /// created after it is set, and the live instance is also what iOS
    /// overrides to white when brightness bottoms out during dim.
    ///
    /// The selected item previously used near-black (white 0.0, tint 0.25)
    /// against a white 0.09 background, while unselected sat at 0.55 — so the
    /// selected tab was both darker than its neighbours and nearly invisible.
    /// Selected is now the theme accent, unselected a dimmer grey.
    static func applyTabBarColors(for theme: AppTheme) {
        // Normal keeps a neutral light selection; its accent is red, which would
        // fight that theme's muted rugged palette.
        let accent = UIColor(theme.isFlat ? theme.galleryAccent : Color(white: 0.9))
        let unselected = UIColor(white: 0.45, alpha: 1)

        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(white: 0.09, alpha: 1)

        let normal = appearance.stackedLayoutAppearance.normal
        normal.iconColor = unselected
        normal.titleTextAttributes = [.foregroundColor: unselected]

        let selected = appearance.stackedLayoutAppearance.selected
        selected.iconColor = accent
        selected.titleTextAttributes = [.foregroundColor: accent]

        UITabBar.appearance().standardAppearance = appearance
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
        UITabBar.appearance().tintColor = accent
        UITabBar.appearance().unselectedItemTintColor = unselected

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first(where: { $0.isKeyWindow })
                        ?? windowScene.windows.first
        else { return }

        for tabBar in findTabBars(in: window) {
            tabBar.standardAppearance = appearance
            if #available(iOS 15.0, *) { tabBar.scrollEdgeAppearance = appearance }
            tabBar.tintColor = accent
            tabBar.unselectedItemTintColor = unselected
        }
    }

    private static func findTabBars(in view: UIView) -> [UITabBar] {
        var found: [UITabBar] = []
        if let tb = view as? UITabBar { found.append(tb) }
        for sub in view.subviews { found += findTabBars(in: sub) }
        return found
    }
}
