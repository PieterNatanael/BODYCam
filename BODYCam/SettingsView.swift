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

    var title: String {
        switch self {
        case .normal: return "NORMAL"
        case .simple: return "SIMPLE"
        }
    }

    var subtitle: String {
        switch self {
        case .normal: return "Rugged textured look, current design"
        case .simple: return "Flat Bauhaus style, bold shapes, no texture"
        }
    }

    var icon: String {
        switch self {
        case .normal: return "circle.grid.cross.fill"
        case .simple: return "square.fill"
        }
    }
}

// MARK: - SettingsView

struct SettingsView: View {

    @AppStorage("CameraDisplayMode") private var displayModeRaw: String = CameraDisplayMode.saveBattery.rawValue
    @AppStorage("AppTheme") private var appThemeRaw: String = AppTheme.normal.rawValue
    @AppStorage("SelectedVideoQuality") private var videoQuality: VideoQuality = .low
    @AppStorage("IsLowLight") private var isLowLight: Bool = false
    @AppStorage("SelectedPhotoQuality") private var photoQuality: PhotoQuality = .high

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
                        sectionLabel("DISPLAY MODE FOR VIDEO TAB")
                        VStack(spacing: 10) {
                            ForEach(CameraDisplayMode.allCases, id: \.self) { mode in
                                modeRow(mode)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        sectionLabel("APPEARANCE FOR VIDEO TAB")
                        VStack(spacing: 10) {
                            ForEach(AppTheme.allCases, id: \.self) { theme in
                                themeRow(theme)
                            }
                        }
                    }

                    previewTipCard

                    videoRecordSection

                    cameraRecordSection

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 24)
            }
        }
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

    // MARK: - Camera Record

    private var cameraRecordSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("CAMERA RECORD")

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

                Text("Tap anywhere on the camera preview to turn it on or off. Tap again to switch it back. Keeping preview off saves battery during long recordings.")
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
