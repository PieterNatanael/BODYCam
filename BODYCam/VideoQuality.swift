import AVFoundation

enum VideoQuality: Int, CaseIterable {
    case low
    case medium
    case high
    case max

    var description: String {
        switch self {
        case .low:    return "Low (480p)"
        case .medium: return "Medium (720p)"
        case .high:   return "High (1080p)"
        case .max:    return "Max (device best)"
        }
    }

    var shortLabel: String {
        switch self {
        case .low:    return "LOW"
        case .medium: return "MED"
        case .high:   return "HIGH"
        case .max:    return "MAX"
        }
    }

    /// Fixed AVFoundation preset for every tier except Max, which instead asks
    /// the device for its own best format (see ContentView.applyQuality) — so
    /// this value is never actually read for .max, and .high here is just a
    /// safe fallback should that ever change.
    var preset: AVCaptureSession.Preset {
        switch self {
        case .low:    return .low
        case .medium: return .medium
        case .high:   return .high
        case .max:    return .high
        }
    }

    /// Minimum free storage required to start a recording at this tier. Low
    /// and Medium are small, bandwidth oriented presets that barely use any
    /// space regardless of device. Max asks for the device's true ceiling
    /// (up to 4K), which can run several MB per second, so it needs a much
    /// larger cushion or the framework's own end of disk safety stop would
    /// hit within seconds of starting.
    var minRecordingStorageMB: Int64 {
        switch self {
        case .low:    return 50
        case .medium: return 50
        case .high:   return 100
        case .max:    return 500
        }
    }
}
