import SwiftUI

// MARK: - App Language

enum AppLanguage: String, CaseIterable {
    case system
    case en, ja, de, fr, zhHans, ko, zhHant, id

    /// Always rendered in that language's own script, regardless of the
    /// app's current display language — so someone who ends up somewhere
    /// they can't read can still recognize their own language by name, the
    /// same convention iOS's own language picker uses. Deliberately a plain
    /// String, not LocalizedStringKey: these must NEVER be looked up and
    /// swapped for a translation of "English"/"German"/etc.
    var nativeName: String {
        switch self {
        case .system: return "System"
        case .en:     return "English"
        case .ja:     return "日本語"
        case .de:     return "Deutsch"
        case .fr:     return "Français"
        case .zhHans: return "简体中文"
        case .ko:     return "한국어"
        case .zhHant: return "繁體中文"
        case .id:     return "Bahasa Indonesia"
        }
    }

    /// Nil for .system, meaning "don't override — follow the device".
    var localeIdentifier: String? {
        switch self {
        case .system: return nil
        case .en:     return "en"
        case .ja:     return "ja"
        case .de:     return "de"
        case .fr:     return "fr"
        case .zhHans: return "zh-Hans"
        case .ko:     return "ko"
        case .zhHant: return "zh-Hant"
        case .id:     return "id"
        }
    }
}

extension Bundle {
    /// The bundle NSLocalizedString-style lookups should read from, honoring
    /// the in-app language override — NSLocalizedString and Bundle.main
    /// always follow the DEVICE's system language and have no way to see
    /// SwiftUI's .environment(\.locale) override, which is what Text() calls
    /// respect. Every hand-written lookup in this app (a handful of strings
    /// that aren't literal Text() calls, like Yapping's default script and a
    /// couple of alert messages) needs to go through this instead of the
    /// bare NSLocalizedString(_:comment:) function, or those specific
    /// strings would silently ignore the in-app override and only respond to
    /// the phone's own language setting.
    static var appPreferred: Bundle {
        let raw = UserDefaults.standard.string(forKey: "AppLanguage") ?? AppLanguage.system.rawValue
        guard let identifier = AppLanguage(rawValue: raw)?.localeIdentifier,
              let path = Bundle.main.path(forResource: identifier, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return .main }
        return bundle
    }
}

// MARK: - Display Mode

enum CameraDisplayMode: String, CaseIterable {
    case saveBattery
    case normal
    case yapping
    case pro

    // LocalizedStringKey rather than String: these flow straight into Text(),
    // and only the LocalizedStringKey overload of Text's initializer actually
    // looks a string up in Localizable.xcstrings — Text(String) just displays
    // the raw value verbatim in every language.
    var title: LocalizedStringKey {
        switch self {
        case .saveBattery: return "SAVE BATTERY MODE"
        case .normal:       return "NORMAL MODE"
        case .yapping:      return "YAPPING MODE"
        case .pro:          return "PRO MODE"
        }
    }

    var subtitle: LocalizedStringKey {
        switch self {
        case .saveBattery: return "Compact preview, lower power use"
        case .normal:       return "Full screen preview, uses more battery"
        case .yapping:      return "Script on screen, preview shrinks to a movable corner"
        case .pro:          return "Compact preview, with manual exposure and focus lock"
        }
    }

    var icon: String {
        switch self {
        case .saveBattery: return "battery.75"
        case .normal:       return "rectangle.fill"
        case .yapping:      return "text.alignleft"
        case .pro:          return "slider.horizontal.3"
        }
    }
}

// MARK: - App Theme

enum AppTheme: String, CaseIterable {
    case normal
    case simple
    case tactical
    case matcha
    case iceCream
    case spider
    case tropical

    var title: LocalizedStringKey {
        switch self {
        case .normal:   return "NORMAL"
        case .simple:   return "SIMPLE"
        case .tactical: return "TACTICAL"
        case .matcha:   return "MATCHA"
        case .iceCream: return "ICE CREAM"
        case .spider:   return "SPIDER"
        case .tropical: return "TROPICAL"
        }
    }

    var subtitle: LocalizedStringKey {
        switch self {
        case .normal:   return "Rugged textured look, current design"
        case .simple:   return "Flat Bauhaus style, bold shapes, no texture"
        case .tactical: return "Night vision HUD, monochrome green"
        case .matcha:   return "Flat and calm, soft green accents"
        case .iceCream: return "Flat and playful, pastel accents"
        case .spider:   return "Red and blue, webbed corners"
        case .tropical: return "Wood brown and coconut white"
        }
    }

    var icon: String {
        switch self {
        case .normal:   return "circle.grid.cross.fill"
        case .simple:   return "square.fill"
        case .tactical: return "viewfinder"
        case .matcha:   return "leaf.fill"
        case .iceCream: return "paintpalette.fill"
        case .spider:   return "network"
        // sun.max.fill rather than a literal palm tree or coconut symbol —
        // SF Symbols only added those in SF Symbols 4 (iOS 16), which would
        // silently render as no icon at all back on this app's iOS 14
        // minimum. See RootView's tab icon fix for the same pitfall.
        case .tropical: return "sun.max.fill"
        }
    }
}

// MARK: - Theme palette
//
// Lives on the enum rather than being repeated in every view that draws themed
// chrome. The views previously each carried their own copy of these colours
// plus `appTheme == .tactical ? green : red` ternaries, which only ever worked
// while there were exactly two flat themes — adding a third would have meant
// nested ternaries in a dozen places across four files.
extension AppTheme {
    /// Simple, Tactical and Matcha share the same flat bones: no gradient, no
    /// texture, sharp corners. Only Normal keeps the rugged treatment.
    var isFlat: Bool { self != .normal }

    /// How the preview frame is drawn. Was a `usesCornerBrackets` boolean while
    /// Tactical was the only theme with a custom frame; Spider needs a third
    /// option, so it is an enum rather than a second parallel flag.
    var previewDecoration: PreviewFrameDecoration {
        switch self {
        case .tactical: return .brackets
        case .spider:   return .web
        default:        return .border
        }
    }

    /// One colour per control, so a theme can be monochrome or multi-coloured
    /// without any call site needing to know which. Replaced an earlier
    /// "one tint, or fall back to Simple's triad" model, which couldn't express
    /// a second multi-coloured theme with its own distinct set.
    private struct Palette {
        let flip: Color
        let dim: Color
        let settings: Color
        let record: Color
        let preview: Color
        let gallery: Color

        /// Themes that tint every control identically.
        static func uniform(_ color: Color) -> Palette {
            Palette(flip: color, dim: color, settings: color,
                    record: color, preview: color, gallery: color)
        }
    }

    // Bauhaus primaries
    private static let simpleRed     = Color(red: 0.85, green: 0.15, blue: 0.1)
    private static let simpleYellow  = Color(red: 0.95, green: 0.78, blue: 0.1)
    private static let simpleBlue    = Color(red: 0.15, green: 0.4,  blue: 0.85)

    private static let tacticalGreen = Color(red: 0.25, green: 0.95, blue: 0.4)
    /// Muted and desaturated, so it reads as calm next to Tactical's near-neon
    /// green while still holding enough contrast against black.
    private static let matchaGreen   = Color(red: 0.52, green: 0.68, blue: 0.45)

    // Ice cream: pastel, but kept saturated enough to stay legible on black —
    // true washed-out pastels disappear against a dark background.
    private static let strawberry    = Color(red: 0.98, green: 0.52, blue: 0.63)
    private static let mint          = Color(red: 0.58, green: 0.87, blue: 0.75)
    private static let vanilla       = Color(red: 0.99, green: 0.85, blue: 0.52)
    private static let blueberry     = Color(red: 0.62, green: 0.70, blue: 0.95)

    // Spider: the suit's scarlet and royal blue, plus a pale silk tone.
    private static let scarlet       = Color(red: 0.86, green: 0.12, blue: 0.16)
    private static let royalBlue     = Color(red: 0.16, green: 0.30, blue: 0.78)
    private static let webSilk       = Color(white: 0.88)

    // Tropical: a rich wood brown carries most controls, with a warm,
    // slightly off-white "coconut" tone standing in for Spider's webSilk —
    // reserved for the dim button, the same role it plays there, since a
    // pale accent reads better on a moon icon than the dark brown would.
    private static let woodBrown     = Color(red: 0.45, green: 0.29, blue: 0.16)
    private static let coconutWhite  = Color(red: 0.96, green: 0.94, blue: 0.87)

    private var palette: Palette {
        switch self {
        case .normal, .simple:
            return Palette(flip: Self.simpleBlue, dim: Self.simpleYellow,
                           settings: Self.simpleRed, record: Self.simpleRed,
                           preview: Self.simpleRed, gallery: Self.simpleRed)
        case .tactical:
            return .uniform(Self.tacticalGreen)
        case .matcha:
            return .uniform(Self.matchaGreen)
        case .iceCream:
            return Palette(flip: Self.blueberry, dim: Self.vanilla,
                           settings: Self.mint, record: Self.strawberry,
                           preview: Self.strawberry, gallery: Self.strawberry)
        case .spider:
            return Palette(flip: Self.royalBlue, dim: Self.webSilk,
                           settings: Self.royalBlue, record: Self.scarlet,
                           preview: Self.scarlet, gallery: Self.scarlet)
        case .tropical:
            return Palette(flip: Self.woodBrown, dim: Self.coconutWhite,
                           settings: Self.woodBrown, record: Self.woodBrown,
                           preview: Self.woodBrown, gallery: Self.woodBrown)
        }
    }

    var flipAccent: Color     { palette.flip }
    var dimAccent: Color      { palette.dim }
    var settingsAccent: Color { palette.settings }
    var recordAccent: Color   { palette.record }
    var previewAccent: Color  { palette.preview }
    /// Single accent for Gallery chrome and thumbnails.
    var galleryAccent: Color  { palette.gallery }

    var previewBorderWidth: CGFloat {
        switch self {
        case .tactical, .spider:                    return 2
        case .simple, .matcha, .iceCream, .tropical: return 3
        case .normal:                                return 1
        }
    }

    /// Gallery screen background. Nil keeps Normal's own textured pattern;
    /// every other flat theme is plain black except Matcha, whose gallery
    /// ground IS the theme colour rather than black behind bordered thumbnails.
    /// A soft glow behind the Save Battery preview card, the theme colour at
    /// its center fading out to black at the screen's edges. Nil for every
    /// theme except Matcha, which otherwise stays plain black like the rest.
    var cameraBackgroundGlow: Color? {
        switch self {
        case .matcha, .iceCream, .spider, .tropical: return galleryAccent
        default:                                     return nil
        }
    }

    var galleryBackground: Color? {
        switch self {
        case .normal:                                 return nil
        case .matcha, .iceCream, .spider, .tropical:  return galleryAccent
        default:                                      return .black
        }
    }
}

/// Button fill used by the Disclaimer and Explain screens. Originally declared
/// in CompassViews.swift alongside Color.lightGray; both moved here when that
/// file (and the removed compass feature it belonged to) was deleted.
var darkButtonGradient: LinearGradient {
    LinearGradient(
        gradient: Gradient(colors: [
            Color(#colorLiteral(red: 0.255, green: 0.275, blue: 0.302, alpha: 1)),
            Color(#colorLiteral(red: 0.392, green: 0.412, blue: 0.435, alpha: 1))
        ]),
        startPoint: .top, endPoint: .bottom
    )
}

extension Color {
    /// Neutral light grey used by the Normal theme's chrome across the Gallery,
    /// both media viewers, and the disclaimer/explain screens. Originally
    /// declared in CompassViews.swift; it moved here when that file (and the
    /// removed compass feature it belonged to) was deleted, since this file is
    /// already where the app's shared colour vocabulary lives.
    static let lightGray = Color(#colorLiteral(red: 0.804, green: 0.804, blue: 0.804, alpha: 1))

    /// Black or white, whichever stays legible on top of this colour. Picked by
    /// Rec. 601 luma, which is plenty for a binary choice and means every theme
    /// accent (and the red delete / green save states) gets a readable glyph
    /// without hand-tuning a foreground per colour.
    var contrastingForeground: Color {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return .white }
        return (0.299 * r + 0.587 * g + 0.114 * b) > 0.6 ? .black : .white
    }
}

/// How a theme frames the camera preview.
enum PreviewFrameDecoration {
    case border    // plain stroked rectangle
    case brackets  // Tactical's viewfinder reticle
    case web       // Spider's corner webs
}

// MARK: - Spider Web Corners
//
// A quarter web in each corner: radial strands fanning out from the corner
// point, crossed by concentric arcs. Drawn as a Shape so it strokes with the
// theme accent exactly like the other frame styles.
struct SpiderWebCorners: Shape {
    var radius: CGFloat = 64
    /// Gaps between radial strands. 4 gaps means 5 strands including both edges.
    var strands: Int = 4
    var rings: Int = 3

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let quarter = CGFloat.pi / 2

        // Each corner with the angle its web sweeps FROM. Angles run clockwise
        // on screen because the y axis points down.
        let corners: [(CGPoint, CGFloat)] = [
            (CGPoint(x: rect.minX, y: rect.minY), 0),          // top left, sweeps right then down
            (CGPoint(x: rect.maxX, y: rect.minY), quarter),    // top right, down then left
            (CGPoint(x: rect.maxX, y: rect.maxY), .pi),        // bottom right, left then up
            (CGPoint(x: rect.minX, y: rect.maxY), .pi * 1.5)   // bottom left, up then right
        ]

        for (origin, start) in corners {
            for i in 0...strands {
                let a = start + quarter * CGFloat(i) / CGFloat(strands)
                p.move(to: origin)
                p.addLine(to: CGPoint(x: origin.x + cos(a) * radius,
                                      y: origin.y + sin(a) * radius))
            }
            for r in 1...rings {
                let rr = radius * CGFloat(r) / CGFloat(rings)
                // Move to the arc's own start, or the path would draw a stray
                // connecting line from wherever the last strand ended.
                p.move(to: CGPoint(x: origin.x + cos(start) * rr,
                                   y: origin.y + sin(start) * rr))
                p.addArc(center: origin, radius: rr,
                         startAngle: .radians(Double(start)),
                         endAngle: .radians(Double(start + quarter)),
                         clockwise: false)
            }
        }
        return p
    }
}

// MARK: - Corner Brackets
//
// Four L-shaped brackets at the corners of a rect — a viewfinder/targeting
// reticle look for the Tactical theme's preview frame, used instead of a
// plain stroked rectangle.
struct CornerBrackets: Shape {
    var length: CGFloat = 22

    func path(in rect: CGRect) -> Path {
        var p = Path()

        // Top-leading
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))

        // Top-trailing
        p.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))

        // Bottom-trailing
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - length, y: rect.maxY))

        // Bottom-leading
        p.move(to: CGPoint(x: rect.minX + length, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - length))

        return p
    }
}

// MARK: - Rule of Thirds Grid
//
// Pro mode's composition aid: two evenly spaced vertical and horizontal
// lines, dividing the preview into a 3x3 grid. Purely a Shape like the frame
// decorations above — no relation to a theme, just overlaid on the preview
// directly wherever it's toggled on.
struct RuleOfThirdsGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()

        let x1 = rect.minX + rect.width / 3
        let x2 = rect.minX + rect.width * 2 / 3
        let y1 = rect.minY + rect.height / 3
        let y2 = rect.minY + rect.height * 2 / 3

        p.move(to: CGPoint(x: x1, y: rect.minY)); p.addLine(to: CGPoint(x: x1, y: rect.maxY))
        p.move(to: CGPoint(x: x2, y: rect.minY)); p.addLine(to: CGPoint(x: x2, y: rect.maxY))
        p.move(to: CGPoint(x: rect.minX, y: y1)); p.addLine(to: CGPoint(x: rect.maxX, y: y1))
        p.move(to: CGPoint(x: rect.minX, y: y2)); p.addLine(to: CGPoint(x: rect.maxX, y: y2))

        return p
    }
}

// MARK: - SettingsView

struct SettingsView: View {

    @Environment(\.presentationMode) private var presentationMode
    @AppStorage("CameraDisplayMode") private var displayModeRaw: String = CameraDisplayMode.saveBattery.rawValue
    @AppStorage("AppTheme") private var appThemeRaw: String = AppTheme.tropical.rawValue
    @AppStorage("AppLanguage") private var appLanguageRaw: String = AppLanguage.system.rawValue
    @AppStorage("SelectedVideoQuality") private var videoQuality: VideoQuality = .high
    @AppStorage("IsLowLight") private var isLowLight: Bool = false
    @AppStorage("SelectedPhotoQuality") private var photoQuality: PhotoQuality = .high
    @AppStorage("ShowThumbnailMetadata") private var showThumbnailMetadata: Bool = false
    // Off by default: unlike the thumbnail toggle above, this one is
    // permanent per file the moment something is captured with it on — read
    // directly from UserDefaults (not through this @AppStorage) by
    // PhotoCaptureDelegate and VideoCaptureDelegate, neither of which is a
    // View and so can't hold an @AppStorage of its own.
    // Default true for new installs — actually enforced by
    // UserDefaults.register(defaults:) in AppDelegate, not this literal
    // alone; see the comment there for why. Kept in sync here so this
    // property wrapper's own initial value agrees with what a fresh install
    // will actually read.
    @AppStorage("ShowDateStamp") private var showDateStamp: Bool = true
    // The same key ContentView/PhotoCameraView's own on-screen toggle button
    // reads and writes — this is another way to reach the identical
    // preference, not a separate one, so the two always agree. Default true:
    // a framing aid rather than a permanent or destructive change to what
    // gets captured, unlike the date stamp above.
    @AppStorage("ShowGridLines") private var showGridLines: Bool = true
    @ObservedObject private var scheduleStore = ScheduleStore.shared
    @State private var showScheduledList = false

    var body: some View {
        ZStack {
            background

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Text("SETTINGS")
                            .font(.system(size: 20, weight: .heavy, design: .monospaced))
                            .tracking(3)
                            .foregroundColor(.white)
                        Spacer()
                        Button(action: { presentationMode.wrappedValue.dismiss() }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 26))
                                .foregroundColor(Color(white: 0.6))
                        }
                    }
                    .padding(.top, 20)

                    VStack(alignment: .leading, spacing: 10) {
                        sectionLabel("DISPLAY MODE")
                        VStack(spacing: 10) {
                            ForEach(CameraDisplayMode.allCases, id: \.self) { mode in
                                modeRow(mode)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        sectionLabel("APPEARANCE")
                        VStack(spacing: 10) {
                            ForEach(AppTheme.allCases, id: \.self) { theme in
                                themeRow(theme)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        sectionLabel("LANGUAGE")
                        VStack(spacing: 10) {
                            ForEach(AppLanguage.allCases, id: \.self) { language in
                                languageRow(language)
                            }
                        }
                    }

                    previewTipCard

                    gridSection

                    videoRecordSection

                    cameraRecordSection

                    gallerySection

                    scheduledSection

                    aboutSection

                    moreAppsSection

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 24)
            }
        }
        .sheet(isPresented: $showScheduledList) {
            ScheduledListSheet(store: scheduleStore)
        }
        .onAppear { scheduleStore.refresh() }
    }

    // MARK: - More From Us
    //
    // Deliberately understated: plain rows rather than the image-and-button
    // treatment of AppCardView, so it reads as a footnote rather than an ad.

    private var moreAppsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("ALSO FROM US")

            appLink(
                icon: "waveform",
                name: "Low Battery Voice Recorder",
                platform: "iPhone",
                url: "https://apps.apple.com/id/app/low-battery-voice-recorder/id6670330613"
            )

            appLink(
                icon: "desktopcomputer",
                name: "GoodMood Screen Companion",
                platform: "Mac",
                url: "https://apps.apple.com/id/app/goodmood-screen-companion/id6765573775?mt=12"
            )
        }
        .padding(16)
        .background(cardBackground)
    }

    private func appLink(icon: String, name: String, platform: String, url: String) -> some View {
        Button(action: {
            guard let link = URL(string: url) else { return }
            UIApplication.shared.open(link)
        }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15))
                    .foregroundColor(Color(white: 0.5))
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(white: 0.7))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    Text(platform)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(Color(white: 0.4))
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(white: 0.3))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Alarms & Reminders

    private var scheduledSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("ALARMS AND REMINDERS")

            Button(action: { showScheduledList = true }) {
                HStack(spacing: 14) {
                    Image(systemName: "alarm.fill")
                        .font(.system(size: 18))
                        .foregroundColor(Color(white: 0.6))
                        .frame(width: 26)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("SCHEDULED")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .tracking(1)
                            .foregroundColor(Color(white: 0.85))
                        Text(scheduleStore.items.isEmpty
                             ? "Nothing scheduled"
                             : "\(scheduleStore.items.count) waiting")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Color(white: 0.4))
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(white: 0.35))
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            Text("Set one from the ⋯ menu when viewing a photo or video in the Gallery.")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Color(white: 0.35))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(cardBackground)
    }

    // MARK: - Video Record

    private var videoRecordSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("VIDEO RECORD")

            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("QUALITY")
                HStack(spacing: 8) {
                    ForEach(VideoQuality.allCases, id: \.self) { q in
                        Button(action: { videoQuality = q }) {
                            Text(q.shortLabel)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .tracking(1)
                                .foregroundColor(videoQuality == q ? .white : Color(white: 0.4))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(qualityBackground(active: videoQuality == q))
                        }
                    }
                }
                if videoQuality == .max {
                    Text("USES SIGNIFICANTLY MORE STORAGE AND BATTERY")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(Color(white: 0.5))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("LOW LIGHT BOOST")
                Button(action: { isLowLight.toggle() }) {
                    HStack(spacing: 8) {
                        Image(systemName: isLowLight ? "moon.fill" : "moon")
                            .font(.system(size: 14))
                        Text(isLowLight ? "ON (30fps boost)" : "OFF (normal mode)")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .tracking(1)
                    }
                    .foregroundColor(isLowLight ? Color(red: 1.0, green: 0.85, blue: 0.4) : Color(white: 0.4))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isLowLight ? Color(red: 0.25, green: 0.2, blue: 0.05) : Color(white: 0.1))
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isLowLight ? Color(red: 0.8, green: 0.65, blue: 0.2) : Color(white: 0.2), lineWidth: 1)
                        }
                    )
                }
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    // MARK: - Photo Capture

    private var cameraRecordSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("PHOTO CAPTURE")

            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("QUALITY")
                HStack(spacing: 8) {
                    ForEach(PhotoQuality.allCases, id: \.self) { q in
                        Button(action: { photoQuality = q }) {
                            Text(q.rawValue)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .tracking(1)
                                .foregroundColor(photoQuality == q ? .white : Color(white: 0.4))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(qualityBackground(active: photoQuality == q))
                        }
                    }
                }
                if photoQuality == .max {
                    Text("USES SIGNIFICANTLY MORE STORAGE")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(Color(white: 0.5))
                }
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("ABOUT")

            Button(action: {
                // Cleared AND announced: RootView read this flag once when it
                // was created, so clearing the default alone would not reopen
                // anything until the next launch.
                UserDefaults.standard.set(false, forKey: "hasSeenOnboarding")
                NotificationCenter.default.post(name: .showOnboardingAgain, object: nil)
                presentationMode.wrappedValue.dismiss()
            }) {
                HStack(spacing: 14) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 18))
                        .foregroundColor(Color(white: 0.6))
                        .frame(width: 26)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("SHOW INTRO AGAIN")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .tracking(1)
                            .foregroundColor(Color(white: 0.85))
                        Text("Permissions and safety notes")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Color(white: 0.4))
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(white: 0.35))
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(cardBackground)
    }

    // MARK: - Gallery

    private var gallerySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("GALLERY")

            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("THUMBNAIL DATE AND TIME")
                Button(action: { showThumbnailMetadata.toggle() }) {
                    HStack(spacing: 8) {
                        Image(systemName: showThumbnailMetadata ? "clock.fill" : "clock")
                            .font(.system(size: 14))
                        Text(showThumbnailMetadata ? "ON" : "OFF")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .tracking(1)
                    }
                    .foregroundColor(showThumbnailMetadata ? Color(white: 0.85) : Color(white: 0.4))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(showThumbnailMetadata ? Color(white: 0.25) : Color(white: 0.1))
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(showThumbnailMetadata ? Color(white: 0.45) : Color(white: 0.2), lineWidth: 1)
                        }
                    )
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                sectionLabel("DATE STAMP ON PHOTOS AND VIDEOS")
                Button(action: { showDateStamp.toggle() }) {
                    HStack(spacing: 8) {
                        Image(systemName: showDateStamp ? "calendar.circle.fill" : "calendar")
                            .font(.system(size: 14))
                        Text(showDateStamp ? "ON" : "OFF")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .tracking(1)
                    }
                    .foregroundColor(showDateStamp ? Color(white: 0.85) : Color(white: 0.4))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(showDateStamp ? Color(white: 0.25) : Color(white: 0.1))
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(showDateStamp ? Color(white: 0.45) : Color(white: 0.2), lineWidth: 1)
                        }
                    )
                }
                // Off by default and said plainly here: unlike the thumbnail
                // toggle above, this one is permanent per file the moment a
                // photo or video is captured with it on — there's no editing
                // it back out afterward.
                Text("Burns the date, time, and LBC onto the photo or video itself. Cannot be removed afterward.")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color(white: 0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(white: 0.08))
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(white: 0.2), lineWidth: 1)
        }
    }

    private func qualityBackground(active: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(active ? Color(white: 0.25) : Color(white: 0.1))
            RoundedRectangle(cornerRadius: 6)
                .stroke(active ? Color(white: 0.5) : Color(white: 0.2), lineWidth: 1)
        }
    }

    // MARK: - Sub-views

    private var background: some View {
        ZStack {
            Image("pattern1").resizable().ignoresSafeArea()
            LinearGradient(
                colors: [.black, Color(#colorLiteral(red: 0.476, green: 0.476, blue: 0.476, alpha: 1))],
                startPoint: .top, endPoint: .bottom
            ).opacity(0.8).ignoresSafeArea()
        }
    }

    private func sectionLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(Color(white: 0.4))
            .tracking(2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var previewTipCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("PREVIEW")
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 18))
                    .foregroundColor(Color(white: 0.5))
                    .frame(width: 26)

                Text("Tap the camera preview to focus on whatever you tapped, like the built in Camera app. To save battery during long recordings, use the moon button to dim the screen.")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Color(white: 0.55))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(white: 0.08))
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(white: 0.2), lineWidth: 1)
                }
            )
        }
    }

    /// The same preference the on-screen grid button (Pro mode's toolbar)
    /// toggles — this just gives it a second, more discoverable home, since
    /// framing help is useful in every display mode, not only Pro.
    private var gridSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("COMPOSITION GRID")
            Button(action: { showGridLines.toggle() }) {
                HStack(spacing: 8) {
                    Image(systemName: showGridLines ? "square.grid.3x3.fill" : "square.grid.3x3")
                        .font(.system(size: 14))
                    Text(showGridLines ? "ON" : "OFF")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .tracking(1)
                }
                .foregroundColor(showGridLines ? Color(white: 0.85) : Color(white: 0.4))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(showGridLines ? Color(white: 0.25) : Color(white: 0.1))
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(showGridLines ? Color(white: 0.45) : Color(white: 0.2), lineWidth: 1)
                    }
                )
            }
            Text("Overlays rule-of-thirds lines on the camera preview, in every display mode. A framing aid only — never appears in a saved photo or video.")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(Color(white: 0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(cardBackground)
    }

    private func modeRow(_ mode: CameraDisplayMode) -> some View {
        let isActive = displayModeRaw == mode.rawValue
        return Button(action: { displayModeRaw = mode.rawValue }) {
            HStack(spacing: 14) {
                Image(systemName: mode.icon)
                    .font(.system(size: 20))
                    .foregroundColor(isActive ? Color(red: 1.0, green: 0.85, blue: 0.4) : Color(white: 0.4))
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(isActive ? .white : Color(white: 0.6))
                    Text(mode.subtitle)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Color(white: 0.4))
                }

                Spacer()

                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(isActive ? Color(red: 1.0, green: 0.85, blue: 0.4) : Color(white: 0.3))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isActive ? Color(white: 0.16) : Color(white: 0.08))
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isActive ? Color(white: 0.4) : Color(white: 0.2), lineWidth: 1)
                }
            )
            .shadow(color: .black.opacity(0.4), radius: 3, x: 1, y: 2)
        }
        .buttonStyle(.plain)
    }

    private func themeRow(_ theme: AppTheme) -> some View {
        let isActive = appThemeRaw == theme.rawValue
        return Button(action: { appThemeRaw = theme.rawValue }) {
            HStack(spacing: 14) {
                Image(systemName: theme.icon)
                    .font(.system(size: 20))
                    .foregroundColor(isActive ? Color(red: 1.0, green: 0.85, blue: 0.4) : Color(white: 0.4))
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(theme.title)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(isActive ? .white : Color(white: 0.6))
                    Text(theme.subtitle)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Color(white: 0.4))
                }

                Spacer()

                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(isActive ? Color(red: 1.0, green: 0.85, blue: 0.4) : Color(white: 0.3))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isActive ? Color(white: 0.16) : Color(white: 0.08))
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isActive ? Color(white: 0.4) : Color(white: 0.2), lineWidth: 1)
                }
            )
            .shadow(color: .black.opacity(0.4), radius: 3, x: 1, y: 2)
        }
        .buttonStyle(.plain)
    }

    private func languageRow(_ language: AppLanguage) -> some View {
        let isActive = appLanguageRaw == language.rawValue
        return Button(action: { appLanguageRaw = language.rawValue }) {
            HStack(spacing: 14) {
                Image(systemName: language == .system ? "iphone" : "globe")
                    .font(.system(size: 20))
                    .foregroundColor(isActive ? Color(red: 1.0, green: 0.85, blue: 0.4) : Color(white: 0.4))
                    .frame(width: 26)

                // nativeName is a plain String by design — it must never be
                // looked up and swapped for a translated version of itself.
                Text(language.nativeName)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(isActive ? .white : Color(white: 0.6))

                Spacer()

                Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(isActive ? Color(red: 1.0, green: 0.85, blue: 0.4) : Color(white: 0.3))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isActive ? Color(white: 0.16) : Color(white: 0.08))
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isActive ? Color(white: 0.4) : Color(white: 0.2), lineWidth: 1)
                }
            )
            .shadow(color: .black.opacity(0.4), radius: 3, x: 1, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
