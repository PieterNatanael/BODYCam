import AVFoundation

enum VideoQuality: Int, CaseIterable {
    case low
    case medium
    case high

    var description: String {
        switch self {
        case .low:    return "Low (480p)"
        case .medium: return "Medium (720p)"
        case .high:   return "High (1080p)"
        }
    }

    var shortLabel: String {
        switch self {
        case .low:    return "LOW"
        case .medium: return "MED"
        case .high:   return "HIGH"
        }
    }

    var preset: AVCaptureSession.Preset {
        switch self {
        case .low:    return .low
        case .medium: return .medium
        case .high:   return .high
        }
    }
}
