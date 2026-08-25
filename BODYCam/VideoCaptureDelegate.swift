import AVFoundation

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

        do {
            // Remove any stale file at the destination (shouldn't happen, but be safe)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
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
}
