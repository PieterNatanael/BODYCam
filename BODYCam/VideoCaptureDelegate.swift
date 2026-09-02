import AVFoundation
import UIKit

// MARK: - Notification names

extension Notification.Name {
    static let recordingStoppedWithError = Notification.Name("recordingStoppedWithError")
    static let screenDidDim      = Notification.Name("screenDidDim")
    static let screenDidWake     = Notification.Name("screenDidWake")
    static let userRequestedWake = Notification.Name("userRequestedWake")
    /// Posted by Settings' "Show intro again" row. RootView owns the
    /// onboarding cover, and Settings is presented as a sheet from a tab, so
    /// there is no binding between them to write through.
    static let showOnboardingAgain = Notification.Name("showOnboardingAgain")
}

// MARK: - Delegate

/// Owns the file-finalization step.
/// We record to a TEMP file, then move it to Documents only after the delegate
/// confirms the recording is complete. This prevents GalleryView from picking
/// up a partial (0-second) file while AVFoundation is still writing the moov atom.
class VideoCaptureDelegate: NSObject, AVCaptureFileOutputRecordingDelegate, ObservableObject {

    /// Set this before calling startRecording(to:recordingDelegate:).
    /// The delegate moves the finished temp file here on success.
    var destinationURL: URL?

    func fileOutput(_ output: AVCaptureFileOutput,
                    didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection],
                    error: Error?) {

        // AVCaptureMovieFileOutput may report a non-fatal error while still
        // saving the file successfully (e.g. max duration reached). Check the
        // dedicated key before deciding whether to treat this as a failure.
        let savedSuccessfully: Bool
        if let nsError = error as NSError?,
           let finished = nsError.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool {
            savedSuccessfully = finished
        } else {
            savedSuccessfully = (error == nil)
        }

        guard savedSuccessfully else {
            // Fatal error — broadcast so ContentView can reset UI and alert
            if let error = error {
                print("Recording stopped with error: \(error.localizedDescription)")
                NotificationCenter.default.post(
                    name: .recordingStoppedWithError,
                    object: nil,
                    userInfo: ["error": error]
                )
            }
            // Clean up the incomplete temp file
            try? FileManager.default.removeItem(at: outputFileURL)
            return
        }

        // Move temp → Documents now that the file is fully finalized
        guard let dest = destinationURL else {
            print("VideoCaptureDelegate: no destinationURL set — recording lost")
            try? FileManager.default.removeItem(at: outputFileURL)
            return
        }

        if FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.removeItem(at: dest)
        }

        // Read straight from UserDefaults rather than an @AppStorage — this
        // class isn't a View and can't hold one.
        if UserDefaults.standard.bool(forKey: "ShowDateStamp") {
            VideoCaptureDelegate.burnDateStamp(sourceURL: outputFileURL, to: dest) { success in
                if success {
                    try? FileManager.default.removeItem(at: outputFileURL)
                    print("Recording saved with date stamp: \(dest.lastPathComponent)")
                } else {
                    // Falls back to the plain recording rather than losing
                    // footage that was already successfully captured just
                    // because the cosmetic stamping pass failed.
                    print("Date stamp export failed — saving without stamp")
                    do {
                        try FileManager.default.moveItem(at: outputFileURL, to: dest)
                    } catch {
                        print("Failed to move recording to Documents: \(error)")
                        NotificationCenter.default.post(
                            name: .recordingStoppedWithError, object: nil, userInfo: ["error": error])
                    }
                }
            }
            return
        }

        do {
            try FileManager.default.moveItem(at: outputFileURL, to: dest)
            print("Recording saved: \(dest.lastPathComponent)")
        } catch {
            print("Failed to move recording to Documents: \(error)")
            NotificationCenter.default.post(
                name: .recordingStoppedWithError,
                object: nil,
                userInfo: ["error": error]
            )
        }
    }

    /// Burns capture date/time and "LBC" onto the finished video, matching
    /// the photo stamp. Done as a separate export pass over the already
    /// finished file, not live during recording — AVCaptureMovieFileOutput
    /// writes video via direct hardware encoding with no per-frame
    /// processing step, and adding one would mean replacing that with the
    /// much heavier AVCaptureVideoDataOutput + AVAssetWriter pipeline this
    /// app deliberately keeps separate for dual camera (see
    /// DualCameraRecorder) rather than using for ordinary single-camera
    /// recording. The cost of doing it this way is a few seconds of
    /// processing after recording stops, roughly proportional to length,
    /// before the clip appears in the Gallery — expected, not a bug.
    static func burnDateStamp(sourceURL: URL, to destinationURL: URL,
                              completion: @escaping (Bool) -> Void) {
        let asset = AVURLAsset(url: sourceURL)
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            completion(false)
            return
        }

        let composition = AVMutableComposition()
        guard let compVideoTrack = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else {
            completion(false)
            return
        }

        do {
            let range = CMTimeRange(start: .zero, duration: asset.duration)
            try compVideoTrack.insertTimeRange(range, of: videoTrack, at: .zero)
            if let audioTrack = asset.tracks(withMediaType: .audio).first,
               let compAudioTrack = composition.addMutableTrack(
                   withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                try compAudioTrack.insertTimeRange(range, of: audioTrack, at: .zero)
            }
        } catch {
            print("Date stamp: failed to build composition — \(error)")
            completion(false)
            return
        }

        // The DISPLAY-oriented size, not the raw encoded pixel dimensions —
        // a portrait recording is commonly encoded "sideways" with a 90
        // degree transform, and rendering at the raw size while ignoring
        // that transform would stamp text into what displays as a corner
        // that isn't actually there.
        let transform = videoTrack.preferredTransform
        let transformedRect = CGRect(origin: .zero, size: videoTrack.naturalSize)
            .applying(transform)
        let displaySize = CGSize(width: abs(transformedRect.width), height: abs(transformedRect.height))
        guard displaySize.width > 0, displaySize.height > 0 else {
            completion(false)
            return
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = displaySize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: composition.duration)
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideoTrack)
        layerInstruction.setTransform(transform, at: .zero)
        instruction.layerInstructions = [layerInstruction]
        videoComposition.instructions = [instruction]

        // Parent layer at the final display size, video underneath, stamp
        // text on top — the standard CoreAnimationTool overlay recipe.
        let parentLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: displaySize)
        let videoLayer = CALayer()
        videoLayer.frame = parentLayer.frame
        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(dateStampTextLayer(displaySize: displaySize))

        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer, in: parentLayer)

        guard let export = AVAssetExportSession(asset: composition,
                                                presetName: AVAssetExportPresetHighestQuality) else {
            completion(false)
            return
        }
        export.outputURL = destinationURL
        export.outputFileType = .mov
        export.videoComposition = videoComposition

        export.exportAsynchronously {
            if export.status != .completed {
                print("Date stamp export failed: \(export.error?.localizedDescription ?? "unknown")")
            }
            completion(export.status == .completed)
        }
    }

    private static func dateStampTextLayer(displaySize: CGSize) -> CATextLayer {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        // Deliberately never localized: a stamp meant to travel with the file
        // anywhere it's shared should read the same regardless of whoever
        // eventually views it, same reasoning as the photo stamp.
        let text = "\(formatter.string(from: Date())) · LBC"

        let fontSize = max(14, displaySize.height * 0.022)
        let margin = displaySize.width * 0.025
        let lineHeight = fontSize * 1.4

        let textLayer = CATextLayer()
        textLayer.string = text
        textLayer.font = CGFont("Menlo-Bold" as CFString)
        textLayer.fontSize = fontSize
        textLayer.foregroundColor = UIColor.white.cgColor
        textLayer.alignmentMode = .right
        textLayer.contentsScale = UIScreen.main.scale
        textLayer.shadowColor = UIColor.black.cgColor
        textLayer.shadowOpacity = 0.9
        textLayer.shadowRadius = 3
        textLayer.shadowOffset = .zero
        textLayer.frame = CGRect(x: margin, y: displaySize.height - margin - lineHeight,
                                 width: displaySize.width - margin * 2, height: lineHeight)
        return textLayer
    }
}
