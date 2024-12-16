import AVFoundation
import SwiftUI

class CameraManager {
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureMovieFileOutput?
    
    func setupCamera(selectedQuality: VideoQuality) -> (AVCaptureSession, AVCaptureMovieFileOutput)? {
        let captureSession = AVCaptureSession()
        
        // Video Input
        guard let videoDevice = AVCaptureDevice.default(for: .video),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice) else {
            print("Failed to access the camera.")
            return nil
        }
        
        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        } else {
            print("Failed to add video input to capture session.")
            return nil
        }
        
        // Audio Input
        guard let audioDevice = AVCaptureDevice.default(for: .audio),
              let audioInput = try? AVCaptureDeviceInput(device: audioDevice) else {
            print("Failed to access the microphone.")
            return nil
        }
        
        if captureSession.canAddInput(audioInput) {
            captureSession.addInput(audioInput)
        } else {
            print("Failed to add audio input to capture session.")
            return nil
        }
        
        // Video Output
        let videoOutput = AVCaptureMovieFileOutput()
        
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
            
            // Set video quality preset
            updateCaptureSessionPreset(captureSession: captureSession, quality: selectedQuality)
            
            videoOutput.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.h264], for: videoOutput.connections.first!)
        } else {
            print("Failed to add video output to capture session.")
            return nil
        }
        
        captureSession.startRunning()
        
        return (captureSession, videoOutput)
    }
    
    func updateCaptureSessionPreset(captureSession: AVCaptureSession, quality: VideoQuality) {
        switch quality {
        case .low:
            captureSession.sessionPreset = .low
        case .medium:
            captureSession.sessionPreset = .medium
        case .high:
            captureSession.sessionPreset = .high
        }
    }
    
    func startRecording(videoOutput: AVCaptureMovieFileOutput, delegate: AVCaptureFileOutputRecordingDelegate) -> URL? {
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let fileURL = paths[0].appendingPathComponent("video\(Date().timeIntervalSince1970).mp4")
        
        do {
            try videoOutput.startRecording(to: fileURL, recordingDelegate: delegate)
            return fileURL
        } catch {
            print("Error starting recording: \(error.localizedDescription)")
            return nil
        }
    }
    
    func stopRecording(videoOutput: AVCaptureMovieFileOutput) {
        if videoOutput.isRecording {
            videoOutput.stopRecording()
        }
    }
}