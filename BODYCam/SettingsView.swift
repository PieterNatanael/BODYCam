import SwiftUI

// MARK: - Display Mode

enum CameraDisplayMode: String, CaseIterable {
    case saveBattery
    case normal

    var title: String {
        switch self {
        case .saveBattery: return "SAVE BATTERY MODE"
        case .normal:       return "NORMAL MODE"
        }
    }

    var subtitle: String {
        switch self {
        case .saveBattery: return "Compact preview, lower power use"
        case .normal:       return "Full screen preview, uses more battery"
        }
    }

    var icon: String {
        switch self {
        case .saveBattery: return "battery.75"
        case .normal:       return "rectangle.fill"
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

    var title: String {
        switch self {
        case .normal:   return "NORMAL"
        case .simple:   return "SIMPLE"
        case .tactical: return "TACTICAL"
        case .matcha:   return "MATCHA"
        case .iceCream: return "ICE CREAM"
        case .spider:   return "SPIDER"
        }
    }

    var subtitle: String {
        switch self {
        case .normal:   return "Rugged textured look, current design"
        case .simple:   return "Flat Bauhaus style, bold shapes, no texture"
        case .tactical: return "Night vision HUD, monochrome green"
        case .matcha:   return "Flat and calm, soft green accents"
        case .iceCream: return "Flat and playful, pastel accents"
        case .spider:   return "Red and blue, webbed corners"
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
        case .tactical, .spider:          return 2
        case .simple, .matcha, .iceCream: return 3
        case .normal:                     return 1
        }
    }
}

extension Color {
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

// MARK: - SettingsView

struct SettingsView: View {

    @AppStorage("CameraDisplayMode") private var displayModeRaw: String = CameraDisplayMode.normal.rawValue
    @AppStorage("AppTheme") private var appThemeRaw: String = AppTheme.simple.rawValue
    @AppStorage("SelectedVideoQuality") private var videoQuality: VideoQuality = .low
    @AppStorage("IsLowLight") private var isLowLight: Bool = false
    @AppStorage("SelectedPhotoQuality") private var photoQuality: PhotoQuality = .high
    @ObservedObject private var scheduleStore = ScheduleStore.shared
    @State private var showScheduledList = false

    var body: some View {
        ZStack {
            background

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("SETTINGS")
                        .font(.system(size: 20, weight: .heavy, design: .monospaced))
                        .tracking(3)
                        .foregroundColor(.white)
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

                    previewTipCard

                    videoRecordSection

                    cameraRecordSection

                    scheduledSection

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

    private func sectionLabel(_ text: String) -> some View {
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
}

// MARK: - Preview

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
