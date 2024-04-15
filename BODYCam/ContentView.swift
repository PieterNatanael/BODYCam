//
//  ContentView.swift
//  BODYCam
//
//  Created by Pieter Yoshua Natanael on 13/04/24.
//

import SwiftUI
import AVFoundation

class VideoCaptureDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("Video recording error: \(error.localizedDescription)")
        }
        print("Video recorded successfully: \(outputFileURL.absoluteString)")
    }
}

struct ContentView: View {
    @State private var isRecording = false
    @State private var captureSession: AVCaptureSession?
    @State private var videoOutput: AVCaptureMovieFileOutput?
    @State private var videoURL: URL?
    private let videoCaptureDelegate = VideoCaptureDelegate()
    @State private var showAd: Bool = false
    @State private var showExplain: Bool = false
    @State private var selectedQuality = VideoQuality.low // Default quality selection
    
    var body: some View {
        ZStack {
            // Background Gradient
            LinearGradient(colors: [Color(#colorLiteral(red: 0.5738074183, green: 0.5655357838, blue: 0, alpha: 1)),.white], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack {
                HStack{
                    Button(action: {
                        showAd = true
                    }) {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white)
                            .padding()
                        Spacer()
                        Button(action: {
                            showExplain = true
                        }) {
                            Image(systemName: "questionmark.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.white)
                                .padding()
                        }
                    }
                }
                Spacer()
                Button(action: {
                    if self.isRecording {
                        self.stopRecording()
                    } else {
                        self.startRecording()
                    }
                }) {
                    Text(self.isRecording ? "Stop " : "Start")
                }
                .font(.title2)
                .padding()
                .frame(width: 233)
                .background(isRecording ? Color(#colorLiteral(red: 1, green: 0.8323456645, blue: 0.4732058644, alpha: 1)) : Color(#colorLiteral(red: 0.3084011078, green: 0.5618229508, blue: 0, alpha: 1)) )
                .cornerRadius(25)
                .foregroundColor(isRecording ? Color.black : Color.white)
                .padding(.bottom, 18)
                
                Button(action: {
                    self.exportVideo()
                }) {
                    Text("Export")
                }
                .font(.title2)
                .padding()
                .frame(width: 233)
                .background( Color(#colorLiteral(red: 0.2605174184, green: 0.2605243921, blue: 0.260520637, alpha: 1)) )
                .cornerRadius(25)
                .foregroundColor(.white)
                Spacer()
            }
            .onAppear {
                self.setupCamera()
            }
            .sheet(isPresented: $showAd) {
                ShowAdView(onConfirm: {
                    showAd = false
                })
            }
            .sheet(isPresented: $showExplain, onDismiss: {
                UserDefaults.standard.set(selectedQuality.rawValue, forKey: "SelectedVideoQuality")
                updateCaptureSessionPreset()
            }) {
                ShowExplainView(captureSession: $captureSession, selectedQuality: $selectedQuality, isPresented: $showExplain)
            }

        }
    }
    
    func setupCamera() {
        DispatchQueue.global().async {
            self.captureSession = AVCaptureSession()
            guard let captureSession = self.captureSession else { return }
            
            // Configure video input
            guard let videoDevice = AVCaptureDevice.default(for: .video) else {
                print("Failed to access the camera.")
                return
            }
            
            do {
                let videoInput = try AVCaptureDeviceInput(device: videoDevice)
                if captureSession.canAddInput(videoInput) {
                    captureSession.addInput(videoInput)
                } else {
                    print("Failed to add video input to capture session.")
                    return
                }
            } catch {
                print("Error creating video input: \(error.localizedDescription)")
                return
            }
            
            // Configure audio input
            guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
                print("Failed to access the microphone.")
                return
            }
            
            do {
                let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                if captureSession.canAddInput(audioInput) {
                    captureSession.addInput(audioInput)
                } else {
                    print("Failed to add audio input to capture session.")
                    return
                }
            } catch {
                print("Error creating audio input: \(error.localizedDescription)")
                return
            }
            
            // Configure video output
            self.videoOutput = AVCaptureMovieFileOutput()
            guard let videoOutput = self.videoOutput else {
                print("Failed to create video output.")
                return
            }
            
            if captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)
                
                // Set default video quality preset
                updateCaptureSessionPreset()
                
                videoOutput.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.h264], for: videoOutput.connections.first!)
            } else {
                print("Failed to add video output to capture session.")
                return
            }
            
            captureSession.startRunning()
        }
    }
    
    func startRecording() {
        guard let videoOutput = self.videoOutput else { return }
        
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let fileURL = paths[0].appendingPathComponent("video\(Date().timeIntervalSince1970).mp4")
        videoOutput.startRecording(to: fileURL, recordingDelegate: videoCaptureDelegate)
        self.isRecording = true
        self.videoURL = fileURL
    }
    
    func stopRecording() {
        guard let videoOutput = self.videoOutput else { return }
        videoOutput.stopRecording()
        self.isRecording = false
    }
    
    func exportVideo() {
        guard let videoURL = self.videoURL else { return }
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            let activityViewController = UIActivityViewController(activityItems: [videoURL], applicationActivities: nil)
            window.rootViewController?.present(activityViewController, animated: true, completion: nil)
        }
    }
    
    func updateCaptureSessionPreset() {
        DispatchQueue.main.async {
            switch selectedQuality {
            case .low:
                captureSession?.sessionPreset = .low
            case .medium:
                captureSession?.sessionPreset = .medium
            case .high:
                captureSession?.sessionPreset = .high
            }
            
            if let videoOutput = self.videoOutput {
                let videoConnection = videoOutput.connections.first
                if let orientation = UIApplication.shared.windows.first?.windowScene?.interfaceOrientation {
                    if videoConnection?.isVideoOrientationSupported ?? false {
                        videoConnection?.videoOrientation = AVCaptureVideoOrientation(rawValue: orientation.rawValue) ?? .portrait
                    }
                }
            }
        }
    }
}


// MARK: - Ad View

struct ShowAdView: View {
    var onConfirm: () -> Void

    var body: some View {
        // Your ad content here...
        ScrollView {
            VStack {
                Text("Behind the Scenes.")
                                    .font(.title)
                                    .padding()
                                    .foregroundColor(.white)

                                // Your ad content here...

                                Text("Thank you for supporting our app! Your contribution helps us continue our work and improve our services. Explore these helpful apps too! ")
                    .font(.title3)
                                    .foregroundColor(.white)
                                    .padding(.horizontal)
                                    .multilineTextAlignment(.center)
                
                Text("iPhone & iPad")
                    .font(/*@START_MENU_TOKEN@*/.title/*@END_MENU_TOKEN@*/)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .background(Color.black)
                    .padding()
                
             
                VStack {
                    // SingLoop Image
                    Image("SingLoop") // Assuming "SingLoop" is the name of your image asset
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 200, height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .padding()

                    // SingLoop Title
                    Text("SingLOOP.")
                        .font(.title)
                        .padding(.bottom, 10)
                        .foregroundColor(.white)

                    // SingLoop Description
                    Text("Record your voice effortlessly, and play it back in a loop.")
                        .font(.title3)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .foregroundColor(.white)

                    // Button to Click with Link
                    Button(action: {
                        if let url = URL(string: "https://apps.apple.com/id/app/sing-l00p/id6480459464") {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        Text("Explore SingLoop")
                            .font(.headline)
                            .padding()
                            .foregroundColor(.white)
                            .background(Color.blue)
                            .cornerRadius(10)
                    }
                    .padding(.top, 20)
                }

             
                
                Text("Insomnia Sheep.")
                    .font(.title)
     //                           .monospaced()
                    .padding()
                    .foregroundColor(.white)
                    .onTapGesture {
                        if let url = URL(string: "https://apps.apple.com/id/app/insomnia-sheep/id6479727431") {
                            UIApplication.shared.open(url)
                        }
                    }
             Text("Design to ease your mind and help you relax leading up to sleep.") // Add your 30 character description here
                                 .font(.title3)
//                                 .italic()
                                 .padding(.horizontal)
                                 .multilineTextAlignment(.center)
                                 .foregroundColor(.white)
                
                Text("TimeTell.")
                    .font(.title)
    //                           .monospaced()
                    .padding()
                    .foregroundColor(.white)
                    .onTapGesture {
                        if let url = URL(string: "https://apps.apple.com/app/time-tell/id6479016269") {
                            UIApplication.shared.open(url)
                        }
                    }
    Text("It will announce the time every 30 seconds, no more guessing and checking your watch, for time-sensitive tasks, workouts, and mindfulness exercises.") // Add your 30 character description here
                    .font(.title3)
//                                 .italic()
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .foregroundColor(.white)
                
                
                           
                           Text("Dry Eye Read.")
                               .font(.title)
     //                           .monospaced()
                               .padding()
                               .foregroundColor(.white)
                               .onTapGesture {
                                   if let url = URL(string: "https://apps.apple.com/id/app/dry-eye-read/id6474282023") {
                                       UIApplication.shared.open(url)
                                   }
                               }
             Text("Go-to solution for a comfortable reading experience, by adjusting font size to suit your preference.") // Add your 30 character description here
                                 .font(.title3)
//                                 .italic()
                                 .multilineTextAlignment(.center)
                                 .padding(.horizontal)
                                 .foregroundColor(.white)
                           
                           Text("iProgramMe.")
                               .font(.title)
     //                           .monospaced()
                               .padding()
                               .foregroundColor(.white)
                               .onTapGesture {
                                   if let url = URL(string: "https://apps.apple.com/id/app/iprogramme/id6470770935") {
                                       UIApplication.shared.open(url)
                                   }
                               }
             Text("Custom affirmations, schedule notifications, stay inspired daily.") // Add your 30 character description here
                                 .font(.title3)
//                                 .italic()
                                 .multilineTextAlignment(.center)
                                 .padding(.horizontal)
                                 .foregroundColor(.white)
                           
                           Text("LoopSpeak.")
                               .font(.title)
     //                           .monospaced()
                               .padding()
                               .foregroundColor(.white)
                               .onTapGesture {
                                   if let url = URL(string: "https://apps.apple.com/id/app/loopspeak/id6473384030") {
                                       UIApplication.shared.open(url)
                                   }
                               }
             Text("Type or paste your text, play in loop, and enjoy hands-free narration.") // Add your 30 character description here
                                 .font(.title3)
//                                 .italic()
                                 .multilineTextAlignment(.center)
                                 .padding(.horizontal)
                                 .foregroundColor(.white)
                           
                      
                           Text("TemptationTrack.")
                               .font(.title)
     //                           .monospaced()
                               .padding()
                               .foregroundColor(.white)
                               .onTapGesture {
                                   if let url = URL(string: "https://apps.apple.com/id/app/temptationtrack/id6471236988") {
                                       UIApplication.shared.open(url)
                                   }
                               }
             Text("One button to track milestones, monitor progress, stay motivated.") // Add your 30 character description here
                                 .font(.title3)
//                                 .italic()
                                 .multilineTextAlignment(.center)
                                 .padding(.horizontal)
                                 .foregroundColor(.white)


               Spacer()

               Button("Close") {
                   // Perform confirmation action
                   onConfirm()
               }
               .font(.title)
               .padding()
               .foregroundColor(.black)
               .background(Color.white)
               .cornerRadius(25.0)
               .padding()
           }
           .padding()
           .background(Color(#colorLiteral(red: 0.5738074183, green: 0.5655357838, blue: 0, alpha: 1)))
           .cornerRadius(15.0)
       .padding()
        }
   }
}

// MARK: - Explanation View

struct ShowExplainView: View {
    @Binding var captureSession: AVCaptureSession?
    @Binding var selectedQuality: VideoQuality // Add this line
    @Binding var isPresented: Bool

    var body: some View {
        ScrollView {
            VStack {
                Text("Video Quality")
                    .font(.title3)
                    .multilineTextAlignment(.center)
                    .padding()
                    .foregroundColor(.white)

                Picker("Video Quality", selection: $selectedQuality) {
                    Text("Low").tag(VideoQuality.low)
                    Text("Medium").tag(VideoQuality.medium)
                    Text("High").tag(VideoQuality.high)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                .foregroundColor(.white)
                
                Text("Users can press start to begin recording video, press stop to stop recording, and press export to export the file. The app overwrites previous data when the start button is pressed again. Please note that the app cannot run in the background; make sure to set the auto-lock to 'Never' so the app won't turn off due to inactivity.")
                    .font(.title)
                    .multilineTextAlignment(.center)
                    .padding()
                    .foregroundColor(.white)

                Spacer()

                Button("Close") {
                    // Perform confirmation action
                    updateCaptureSessionPreset()
                    isPresented = false
                }
                .font(.title)
                .padding()
                .foregroundColor(.black)
                .background(Color.white)
                .cornerRadius(25.0)
                .padding()
            }
            .padding()
            .background(Color(#colorLiteral(red: 0.5738074183, green: 0.5655357838, blue: 0, alpha: 1)))
            .cornerRadius(15.0)
            .padding()
        }
        .onDisappear {
            // Save the selected quality when the sheet is closed
            UserDefaults.standard.set(selectedQuality.rawValue, forKey: "SelectedVideoQuality")
        }
        .onAppear {
            // Load the selected quality when the sheet appears
            if let storedQuality = UserDefaults.standard.value(forKey: "SelectedVideoQuality") as? Int,
               let quality = VideoQuality(rawValue: storedQuality) {
                selectedQuality = quality
            }
        }
    }

    func updateCaptureSessionPreset() {
        switch selectedQuality {
        case .low:
            captureSession?.sessionPreset = .low
        case .medium:
            captureSession?.sessionPreset = .medium
        case .high:
            captureSession?.sessionPreset = .high
        }
    }
}


// Enum for video quality options
enum VideoQuality: Int, CaseIterable {
    case low
    case medium
    case high
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}


/*
 //ini good and submit ke app store, namun mau coba add watermark
 
import SwiftUI
import AVFoundation

class VideoCaptureDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("Video recording error: \(error.localizedDescription)")
        }
        print("Video recorded successfully: \(outputFileURL.absoluteString)")
    }
}

struct ContentView: View {
    @State private var isRecording = false
    @State private var captureSession: AVCaptureSession?
    @State private var videoOutput: AVCaptureMovieFileOutput?
    @State private var videoURL: URL?
    private let videoCaptureDelegate = VideoCaptureDelegate()
    @State private var showAd: Bool = false
    @State private var showExplain: Bool = false

    var body: some View {
        ZStack {
            // Background Gradient
            LinearGradient(colors: [Color(#colorLiteral(red: 0.5738074183, green: 0.5655357838, blue: 0, alpha: 1)),.white], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack {
                HStack{
                    Button(action: {
                        showAd = true
                    }) {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white)
                            .padding()
                        Spacer()
                        Button(action: {
                            showExplain = true
                        }) {
                            Image(systemName: "questionmark.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.white)
                                .padding()
                        }
                    }
                }
                Spacer()
                Button(action: {
                    if self.isRecording {
                        self.stopRecording()
                    } else {
                        self.startRecording()
                    }
                }) {
                    Text(self.isRecording ? "Stop " : "Start")
                }
                .font(.title2)
                
                .padding()
                .frame(width: 233)
                .background(isRecording ? Color(#colorLiteral(red: 0.8446564078, green: 0.5145705342, blue: 1, alpha: 1)) : Color(#colorLiteral(red: 0.5818830132, green: 0.2156915367, blue: 1, alpha: 1)) )
                
                .cornerRadius(25)
                .foregroundColor(isRecording ? Color.black : Color.white)
                .padding(.bottom, 18)
                
                Button(action: {
                    self.exportVideo()
                }) {
                    Text("Export")
                }
                .font(.title2)
                
                .padding()
                .frame(width: 233)
                .background( Color(#colorLiteral(red: 0.2605174184, green: 0.2605243921, blue: 0.260520637, alpha: 1)) )
                
                .cornerRadius(25)
                .foregroundColor(.white)
                Spacer()
            }
            .onAppear {
                self.setupCamera()
        }
            .sheet(isPresented: $showAd) {
                ShowAdView(onConfirm: {
                    showAd = false
                })
            }
            
            .sheet(isPresented: $showExplain) {
                ShowExplainView(onConfirm: {
                    showExplain = false
                })
            }
            
        }
    }

    func setupCamera() {
        DispatchQueue.global().async {
            self.captureSession = AVCaptureSession()
            guard let captureSession = self.captureSession else { return }

            // Configure video input
            guard let videoDevice = AVCaptureDevice.default(for: .video) else {
                print("Failed to access the camera.")
                return
            }

            do {
                let videoInput = try AVCaptureDeviceInput(device: videoDevice)
                if captureSession.canAddInput(videoInput) {
                    captureSession.addInput(videoInput)
                } else {
                    print("Failed to add video input to capture session.")
                    return
                }
            } catch {
                print("Error creating video input: \(error.localizedDescription)")
                return
            }

            // Configure audio input
            guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
                print("Failed to access the microphone.")
                return
            }

            do {
                let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                if captureSession.canAddInput(audioInput) {
                    captureSession.addInput(audioInput)
                } else {
                    print("Failed to add audio input to capture session.")
                    return
                }
            } catch {
                print("Error creating audio input: \(error.localizedDescription)")
                return
            }

            // Configure video output
            self.videoOutput = AVCaptureMovieFileOutput()
            guard let videoOutput = self.videoOutput else {
                print("Failed to create video output.")
                return
            }

            if captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)

                // Set video quality preset
                if captureSession.canSetSessionPreset(.low) {
                    captureSession.sessionPreset = .medium
                } else {
                    print("Failed to set session preset.")
                    return
                }

                videoOutput.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.h264], for: videoOutput.connections.first!)
            } else {
                print("Failed to add video output to capture session.")
                return
            }

            captureSession.startRunning()
        }
    }


    func startRecording() {
        guard let videoOutput = self.videoOutput else { return }

        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let fileURL = paths[0].appendingPathComponent("video\(Date().timeIntervalSince1970).mp4")
        videoOutput.startRecording(to: fileURL, recordingDelegate: videoCaptureDelegate)
        self.isRecording = true
        self.videoURL = fileURL
    }

    func stopRecording() {
        guard let videoOutput = self.videoOutput else { return }
        videoOutput.stopRecording()
        self.isRecording = false
    }

    func exportVideo() {
        guard let videoURL = self.videoURL else { return }
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            let activityViewController = UIActivityViewController(activityItems: [videoURL], applicationActivities: nil)
            window.rootViewController?.present(activityViewController, animated: true, completion: nil)
        }
    }
}

#Preview {
    ContentView()}

// MARK: - Ad View

struct ShowAdView: View {
    var onConfirm: () -> Void

    var body: some View {
        // Your ad content here...
        ScrollView {
            VStack {
                Text("Behind the Scenes.")
                                    .font(.title)
                                    .padding()
                                    .foregroundColor(.white)

                                // Your ad content here...

                                Text("Thank you for buying our app with a one-time fee, it helps us keep up the good work. Explore these helpful apps as well. ")
                    .font(.title3)
                                    .foregroundColor(.white)
                                    .padding(.horizontal)
                                    .multilineTextAlignment(.center)
                
                
                
             
             Text("SingLOOP.")
                 .font(.title)
 //                           .monospaced()
                 .padding()
                 .foregroundColor(.white)
                 .onTapGesture {
                     if let url = URL(string: "https://apps.apple.com/id/app/sing-l00p/id6480459464") {
                         UIApplication.shared.open(url)
                     }
                 }
 Text("Record your voice effortlessly, and play it back in a loop.") // Add your 30 character description here
                    .font(.title3)
//                    .italic()
                   .multilineTextAlignment(.center)
                   .padding(.horizontal)
                   .foregroundColor(.white)
             
                
                Text("Insomnia Sheep.")
                    .font(.title)
     //                           .monospaced()
                    .padding()
                    .foregroundColor(.white)
                    .onTapGesture {
                        if let url = URL(string: "https://apps.apple.com/id/app/insomnia-sheep/id6479727431") {
                            UIApplication.shared.open(url)
                        }
                    }
             Text("Design to ease your mind and help you relax leading up to sleep.") // Add your 30 character description here
                                 .font(.title3)
//                                 .italic()
                                 .padding(.horizontal)
                                 .multilineTextAlignment(.center)
                                 .foregroundColor(.white)
                
                Text("TimeTell.")
                    .font(.title)
    //                           .monospaced()
                    .padding()
                    .foregroundColor(.white)
                    .onTapGesture {
                        if let url = URL(string: "https://apps.apple.com/app/time-tell/id6479016269") {
                            UIApplication.shared.open(url)
                        }
                    }
    Text("It will announce the time every 30 seconds, no more guessing and checking your watch, for time-sensitive tasks, workouts, and mindfulness exercises.") // Add your 30 character description here
                    .font(.title3)
//                                 .italic()
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                    .foregroundColor(.white)
                
                
                           
                           Text("Dry Eye Read.")
                               .font(.title)
     //                           .monospaced()
                               .padding()
                               .foregroundColor(.white)
                               .onTapGesture {
                                   if let url = URL(string: "https://apps.apple.com/id/app/dry-eye-read/id6474282023") {
                                       UIApplication.shared.open(url)
                                   }
                               }
             Text("Go-to solution for a comfortable reading experience, by adjusting font size to suit your preference.") // Add your 30 character description here
                                 .font(.title3)
//                                 .italic()
                                 .multilineTextAlignment(.center)
                                 .padding(.horizontal)
                                 .foregroundColor(.white)
                           
                           Text("iProgramMe.")
                               .font(.title)
     //                           .monospaced()
                               .padding()
                               .foregroundColor(.white)
                               .onTapGesture {
                                   if let url = URL(string: "https://apps.apple.com/id/app/iprogramme/id6470770935") {
                                       UIApplication.shared.open(url)
                                   }
                               }
             Text("Custom affirmations, schedule notifications, stay inspired daily.") // Add your 30 character description here
                                 .font(.title3)
//                                 .italic()
                                 .multilineTextAlignment(.center)
                                 .padding(.horizontal)
                                 .foregroundColor(.white)
                           
                           Text("LoopSpeak.")
                               .font(.title)
     //                           .monospaced()
                               .padding()
                               .foregroundColor(.white)
                               .onTapGesture {
                                   if let url = URL(string: "https://apps.apple.com/id/app/loopspeak/id6473384030") {
                                       UIApplication.shared.open(url)
                                   }
                               }
             Text("Type or paste your text, play in loop, and enjoy hands-free narration.") // Add your 30 character description here
                                 .font(.title3)
//                                 .italic()
                                 .multilineTextAlignment(.center)
                                 .padding(.horizontal)
                                 .foregroundColor(.white)
                           
                      
                           Text("TemptationTrack.")
                               .font(.title)
     //                           .monospaced()
                               .padding()
                               .foregroundColor(.white)
                               .onTapGesture {
                                   if let url = URL(string: "https://apps.apple.com/id/app/temptationtrack/id6471236988") {
                                       UIApplication.shared.open(url)
                                   }
                               }
             Text("One button to track milestones, monitor progress, stay motivated.") // Add your 30 character description here
                                 .font(.title3)
//                                 .italic()
                                 .multilineTextAlignment(.center)
                                 .padding(.horizontal)
                                 .foregroundColor(.white)


               Spacer()

               Button("Close") {
                   // Perform confirmation action
                   onConfirm()
               }
               .font(.title)
               .padding()
               .foregroundColor(.black)
               .background(Color.white)
               .cornerRadius(25.0)
               .padding()
           }
           .padding()
           .background(Color(#colorLiteral(red: 0.5738074183, green: 0.5655357838, blue: 0, alpha: 1)))
           .cornerRadius(15.0)
       .padding()
        }
   }
}

    


// MARK: - Explanation View

struct ShowExplainView: View {
    var onConfirm: () -> Void

    var body: some View {
        // Explanation content...
        ScrollView {
            VStack {
                Text("Users can press start to begin recording video, press stop to stop recording, and press export to export the file. The app overwrites previous data when the start button is pressed again. Please note that the app cannot run in the background; make sure to set the auto-lock to 'Never' so the app won't turn off due to inactivity.")
                    .font(.title)
                    .multilineTextAlignment(.center)
     //                       .monospaced()
                    .padding()
                    .foregroundColor(.white)



                Spacer()

                Button("Close") {
                    // Perform confirmation action
                    onConfirm()
                }
                .font(.title)
                .padding()
                .foregroundColor(.black)
                .background(Color.white)
                .cornerRadius(25.0)
                .padding()
            }
            .padding()
            .background(Color(#colorLiteral(red: 0.5738074183, green: 0.5655357838, blue: 0, alpha: 1)))
            .cornerRadius(15.0)
        .padding()
        }
    }
 }

*/
/*

//work well but try to make it work on background
import SwiftUI
import AVFoundation

class VideoCaptureDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("Video recording error: \(error.localizedDescription)")
        }
        print("Video recorded successfully: \(outputFileURL.absoluteString)")
    }
}

struct ContentView: View {
    @State private var isRecording = false
    @State private var captureSession: AVCaptureSession?
    @State private var videoOutput: AVCaptureMovieFileOutput?
    @State private var videoURL: URL?
    private let videoCaptureDelegate = VideoCaptureDelegate()
    @State private var showAd: Bool = false
    @State private var showExplain: Bool = false

    var body: some View {
        ZStack {
            // Background Gradient
            LinearGradient(colors: [Color(#colorLiteral(red: 0.5738074183, green: 0.5655357838, blue: 0, alpha: 1)),.white], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack {
                HStack{
                    Button(action: {
                        showAd = true
                    }) {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white)
                            .padding()
                        Spacer()
                        Button(action: {
                            showExplain = true
                        }) {
                            Image(systemName: "questionmark.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.white)
                                .padding()
                        }
                    }
                }
                Spacer()
                Button(action: {
                    if self.isRecording {
                        self.stopRecording()
                    } else {
                        self.startRecording()
                    }
                }) {
                    Text(self.isRecording ? "Stop Recording" : "Start Recording")
                }
                .font(.title2)
                
                .padding()
                .frame(width: 233)
                .background(isRecording ? Color(#colorLiteral(red: 0.8446564078, green: 0.5145705342, blue: 1, alpha: 1)) : Color(#colorLiteral(red: 0.5818830132, green: 0.2156915367, blue: 1, alpha: 1)) )
                
                .cornerRadius(25)
                .foregroundColor(isRecording ? Color.black : Color.white)
                Button(action: {
                    self.exportVideo()
                }) {
                    Text("Export Video")
                }
                .font(.title2)
                
                .padding()
                .frame(width: 233)
                .background( Color(#colorLiteral(red: 0.9994240403, green: 0.9855536819, blue: 0, alpha: 1)) )
                
                .cornerRadius(25)
                .foregroundColor(.black)
                Spacer()
            }
            .onAppear {
                self.setupCamera()
        }
            .sheet(isPresented: $showAd) {
                ShowAdView(onConfirm: {
                    showAd = false
                })
            }
            
            .sheet(isPresented: $showExplain) {
                ShowExplainView(onConfirm: {
                    showExplain = false
                })
            }
            
        }
    }

    func setupCamera() {
        DispatchQueue.global().async {
            self.captureSession = AVCaptureSession()
            guard let captureSession = self.captureSession else { return }

            // Configure video input
            guard let videoDevice = AVCaptureDevice.default(for: .video) else {
                print("Failed to access the camera.")
                return
            }

            do {
                let videoInput = try AVCaptureDeviceInput(device: videoDevice)
                if captureSession.canAddInput(videoInput) {
                    captureSession.addInput(videoInput)
                } else {
                    print("Failed to add video input to capture session.")
                    return
                }
            } catch {
                print("Error creating video input: \(error.localizedDescription)")
                return
            }

            // Configure audio input
            guard let audioDevice = AVCaptureDevice.default(for: .audio) else {
                print("Failed to access the microphone.")
                return
            }

            do {
                let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                if captureSession.canAddInput(audioInput) {
                    captureSession.addInput(audioInput)
                } else {
                    print("Failed to add audio input to capture session.")
                    return
                }
            } catch {
                print("Error creating audio input: \(error.localizedDescription)")
                return
            }

            // Configure video output
            self.videoOutput = AVCaptureMovieFileOutput()
            guard let videoOutput = self.videoOutput else {
                print("Failed to create video output.")
                return
            }

            if captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)

                // Set video quality preset
                if captureSession.canSetSessionPreset(.low) {
                    captureSession.sessionPreset = .medium
                } else {
                    print("Failed to set session preset.")
                    return
                }

                videoOutput.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.h264], for: videoOutput.connections.first!)
            } else {
                print("Failed to add video output to capture session.")
                return
            }

            captureSession.startRunning()
        }
    }


    func startRecording() {
        guard let videoOutput = self.videoOutput else { return }

        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let fileURL = paths[0].appendingPathComponent("video\(Date().timeIntervalSince1970).mp4")
        videoOutput.startRecording(to: fileURL, recordingDelegate: videoCaptureDelegate)
        self.isRecording = true
        self.videoURL = fileURL
    }

    func stopRecording() {
        guard let videoOutput = self.videoOutput else { return }
        videoOutput.stopRecording()
        self.isRecording = false
    }

    func exportVideo() {
        guard let videoURL = self.videoURL else { return }
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            let activityViewController = UIActivityViewController(activityItems: [videoURL], applicationActivities: nil)
            window.rootViewController?.present(activityViewController, animated: true, completion: nil)
        }
    }
}

#Preview {
    ContentView()}

// MARK: - Ad View

struct ShowAdView: View {
    var onConfirm: () -> Void

    var body: some View {
        // Your ad content here...
        ScrollView {
            VStack {
                Text("Behind the Scenes.")
                                    .font(.title)
                                    .padding()
                                    .foregroundColor(.white)

                                // Your ad content here...

                                Text("Thank you for buying our app with a one-time fee, it helps us keep up the good work. Explore these helpful apps as well. ")
                    .font(.title3)
                                    .foregroundColor(.white)
                                    .padding(.horizontal)
                                    .multilineTextAlignment(.center)
                
                
                
             
             Text("SingLOOP.")
                 .font(.title)
 //                           .monospaced()
                 .padding()
                 .foregroundColor(.white)
                 .onTapGesture {
                     if let url = URL(string: "https://apps.apple.com/id/app/sing-l00p/id6480459464") {
                         UIApplication.shared.open(url)
                     }
                 }
 Text("Record your voice effortlessly, and play it back in a loop.") // Add your 30 character description here
                    .font(.title3)
//                    .italic()
                   .multilineTextAlignment(.center)
                   .padding(.horizontal)
                   .foregroundColor(.white)
             
                
                Text("Insomnia Sheep.")
                    .font(.title)
     //                           .monospaced()
                    .padding()
                    .foregroundColor(.white)
                    .onTapGesture {
                        if let url = URL(string: "https://apps.apple.com/id/app/insomnia-sheep/id6479727431") {
                            UIApplication.shared.open(url)
                        }
                    }
             Text("Design to ease your mind and help you relax leading up to sleep.") // Add your 30 character description here
                                 .font(.title3)
//                                 .italic()
                                 .padding(.horizontal)
                                 .multilineTextAlignment(.center)
                                 .foregroundColor(.white)
                           
                           Text("Dry Eye Read.")
                               .font(.title)
     //                           .monospaced()
                               .padding()
                               .foregroundColor(.white)
                               .onTapGesture {
                                   if let url = URL(string: "https://apps.apple.com/id/app/dry-eye-read/id6474282023") {
                                       UIApplication.shared.open(url)
                                   }
                               }
             Text("Go-to solution for a comfortable reading experience, by adjusting font size to suit your preference.") // Add your 30 character description here
                                 .font(.title3)
//                                 .italic()
                                 .multilineTextAlignment(.center)
                                 .padding(.horizontal)
                                 .foregroundColor(.white)
                           
                           Text("iProgramMe.")
                               .font(.title)
     //                           .monospaced()
                               .padding()
                               .foregroundColor(.white)
                               .onTapGesture {
                                   if let url = URL(string: "https://apps.apple.com/id/app/iprogramme/id6470770935") {
                                       UIApplication.shared.open(url)
                                   }
                               }
             Text("Custom affirmations, schedule notifications, stay inspired daily.") // Add your 30 character description here
                                 .font(.title3)
//                                 .italic()
                                 .multilineTextAlignment(.center)
                                 .padding(.horizontal)
                                 .foregroundColor(.white)
                           
                           Text("LoopSpeak.")
                               .font(.title)
     //                           .monospaced()
                               .padding()
                               .foregroundColor(.white)
                               .onTapGesture {
                                   if let url = URL(string: "https://apps.apple.com/id/app/loopspeak/id6473384030") {
                                       UIApplication.shared.open(url)
                                   }
                               }
             Text("Type or paste your text, play in loop, and enjoy hands-free narration.") // Add your 30 character description here
                                 .font(.title3)
//                                 .italic()
                                 .multilineTextAlignment(.center)
                                 .padding(.horizontal)
                                 .foregroundColor(.white)
                           
                      
                           Text("TemptationTrack.")
                               .font(.title)
     //                           .monospaced()
                               .padding()
                               .foregroundColor(.white)
                               .onTapGesture {
                                   if let url = URL(string: "https://apps.apple.com/id/app/temptationtrack/id6471236988") {
                                       UIApplication.shared.open(url)
                                   }
                               }
             Text("One button to track milestones, monitor progress, stay motivated.") // Add your 30 character description here
                                 .font(.title3)
//                                 .italic()
                                 .multilineTextAlignment(.center)
                                 .padding(.horizontal)
                                 .foregroundColor(.white)


               Spacer()

               Button("Close") {
                   // Perform confirmation action
                   onConfirm()
               }
               .font(.title)
               .padding()
               .foregroundColor(.black)
               .background(Color.white)
               .cornerRadius(25.0)
               .padding()
           }
           .padding()
           .background(Color(#colorLiteral(red: 0, green: 0.5898008943, blue: 1, alpha: 1)))
           .cornerRadius(15.0)
       .padding()
        }
   }
}

    


// MARK: - Explanation View

struct ShowExplainView: View {
    var onConfirm: () -> Void

    var body: some View {
        // Explanation content...
        VStack {
            Text("Press start to begin the timer, and it will remind you every 30 seconds interval.")
                .font(.title)
                .multilineTextAlignment(.center)
 //                       .monospaced()
                .padding()
                .foregroundColor(.white)



            Spacer()

            Button("Close") {
                // Perform confirmation action
                onConfirm()
            }
            .font(.title)
            .padding()
            .foregroundColor(.black)
            .background(Color.white)
            .cornerRadius(25.0)
            .padding()
        }
        .padding()
        .background(Color(#colorLiteral(red: 0, green: 0.5898008943, blue: 1, alpha: 1)))
        .cornerRadius(15.0)
        .padding()
    }
 }
  
*/
/*
//work well but want to add sound
import SwiftUI
import AVFoundation

class VideoCaptureDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("Video recording error: \(error.localizedDescription)")
        }
        print("Video recorded successfully: \(outputFileURL.absoluteString)")
    }
}

struct ContentView: View {
    @State private var isRecording = false
    @State private var captureSession: AVCaptureSession?
    @State private var videoOutput: AVCaptureMovieFileOutput?
    @State private var videoURL: URL?
    private let videoCaptureDelegate = VideoCaptureDelegate()
    @State private var showAd: Bool = false
    @State private var showExplain: Bool = false

    var body: some View {
        ZStack {
            // Background Gradient
            LinearGradient(colors: [Color(#colorLiteral(red: 0.5738074183, green: 0.5655357838, blue: 0, alpha: 1)),.white], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack {
                HStack{
                    Button(action: {
                        showAd = true
                    }) {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white)
                            .padding()
                        Spacer()
                        Button(action: {
                            showExplain = true
                        }) {
                            Image(systemName: "questionmark.circle.fill")
                                .font(.system(size: 30))
                                .foregroundColor(.white)
                                .padding()
                        }
                    }
                }
                Spacer()
                Button(action: {
                    if self.isRecording {
                        self.stopRecording()
                    } else {
                        self.startRecording()
                    }
                }) {
                    Text(self.isRecording ? "Stop Recording" : "Start Recording")
                }
                .font(.title2)
                
                .padding()
                .frame(width: 233)
                .background(isRecording ? Color(#colorLiteral(red: 0.8446564078, green: 0.5145705342, blue: 1, alpha: 1)) : Color(#colorLiteral(red: 0.5818830132, green: 0.2156915367, blue: 1, alpha: 1)) )
                
                .cornerRadius(25)
                .foregroundColor(.black)
                Button(action: {
                    self.exportVideo()
                }) {
                    Text("Export Video")
                }
                .font(.title2)
                
                .padding()
                .frame(width: 233)
                .background(isRecording ? Color(#colorLiteral(red: 0.9994240403, green: 0.9855536819, blue: 0, alpha: 1)) : Color(#colorLiteral(red: 1, green: 0.5212053061, blue: 1, alpha: 1)) )
                
                .cornerRadius(25)
                .foregroundColor(.black)
                Spacer()
            }
            .onAppear {
                self.setupCamera()
        }
            .sheet(isPresented: $showAd) {
                ShowAdView(onConfirm: {
                    showAd = false
                })
            }
            
            .sheet(isPresented: $showExplain) {
                ShowExplainView(onConfirm: {
                    showExplain = false
                })
            }
            
        }
    }

    func setupCamera() {
        DispatchQueue.global().async {
            self.captureSession = AVCaptureSession()
            guard let captureSession = self.captureSession else { return }

            // Configure video input
            guard let videoDevice = AVCaptureDevice.default(for: .video) else {
                print("Failed to access the camera.")
                return
            }

            do {
                let videoInput = try AVCaptureDeviceInput(device: videoDevice)
                if captureSession.canAddInput(videoInput) {
                    captureSession.addInput(videoInput)
                } else {
                    print("Failed to add video input to capture session.")
                    return
                }
            } catch {
                print("Error creating video input: \(error.localizedDescription)")
                return
            }

            // Configure video output
            self.videoOutput = AVCaptureMovieFileOutput()
            guard let videoOutput = self.videoOutput else {
                print("Failed to create video output.")
                return
            }

            if captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)

                // Set video quality preset
                if captureSession.canSetSessionPreset(.low) {
                    captureSession.sessionPreset = .medium
                } else {
                    print("Failed to set session preset.")
                    return
                }

                videoOutput.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.h264], for: videoOutput.connections.first!)
            } else {
                print("Failed to add video output to capture session.")
                return
            }

            captureSession.startRunning()
        }
    }

    func startRecording() {
        guard let videoOutput = self.videoOutput else { return }

        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let fileURL = paths[0].appendingPathComponent("video\(Date().timeIntervalSince1970).mp4")
        videoOutput.startRecording(to: fileURL, recordingDelegate: videoCaptureDelegate)
        self.isRecording = true
        self.videoURL = fileURL
    }

    func stopRecording() {
        guard let videoOutput = self.videoOutput else { return }
        videoOutput.stopRecording()
        self.isRecording = false
    }

    func exportVideo() {
        guard let videoURL = self.videoURL else { return }
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            let activityViewController = UIActivityViewController(activityItems: [videoURL], applicationActivities: nil)
            window.rootViewController?.present(activityViewController, animated: true, completion: nil)
        }
    }
}

#Preview {
    ContentView()}

// MARK: - Ad View

struct ShowAdView: View {
    var onConfirm: () -> Void

    var body: some View {
        // Your ad content here...
        ScrollView {
            VStack {
                Text("Behind the Scenes.")
                                    .font(.title)
                                    .padding()
                                    .foregroundColor(.white)

                                // Your ad content here...

                                Text("Thank you for buying our app with a one-time fee, it helps us keep up the good work. Explore these helpful apps as well. ")
                    .font(.title3)
                                    .foregroundColor(.white)
                                    .padding(.horizontal)
                                    .multilineTextAlignment(.center)
                
                
                
             
             Text("SingLOOP.")
                 .font(.title)
 //                           .monospaced()
                 .padding()
                 .foregroundColor(.white)
                 .onTapGesture {
                     if let url = URL(string: "https://apps.apple.com/id/app/sing-l00p/id6480459464") {
                         UIApplication.shared.open(url)
                     }
                 }
 Text("Record your voice effortlessly, and play it back in a loop.") // Add your 30 character description here
                    .font(.title3)
//                    .italic()
                   .multilineTextAlignment(.center)
                   .padding(.horizontal)
                   .foregroundColor(.white)
             
                
                Text("Insomnia Sheep.")
                    .font(.title)
     //                           .monospaced()
                    .padding()
                    .foregroundColor(.white)
                    .onTapGesture {
                        if let url = URL(string: "https://apps.apple.com/id/app/insomnia-sheep/id6479727431") {
                            UIApplication.shared.open(url)
                        }
                    }
             Text("Design to ease your mind and help you relax leading up to sleep.") // Add your 30 character description here
                                 .font(.title3)
//                                 .italic()
                                 .padding(.horizontal)
                                 .multilineTextAlignment(.center)
                                 .foregroundColor(.white)
                           
                           Text("Dry Eye Read.")
                               .font(.title)
     //                           .monospaced()
                               .padding()
                               .foregroundColor(.white)
                               .onTapGesture {
                                   if let url = URL(string: "https://apps.apple.com/id/app/dry-eye-read/id6474282023") {
                                       UIApplication.shared.open(url)
                                   }
                               }
             Text("Go-to solution for a comfortable reading experience, by adjusting font size to suit your preference.") // Add your 30 character description here
                                 .font(.title3)
//                                 .italic()
                                 .multilineTextAlignment(.center)
                                 .padding(.horizontal)
                                 .foregroundColor(.white)
                           
                           Text("iProgramMe.")
                               .font(.title)
     //                           .monospaced()
                               .padding()
                               .foregroundColor(.white)
                               .onTapGesture {
                                   if let url = URL(string: "https://apps.apple.com/id/app/iprogramme/id6470770935") {
                                       UIApplication.shared.open(url)
                                   }
                               }
             Text("Custom affirmations, schedule notifications, stay inspired daily.") // Add your 30 character description here
                                 .font(.title3)
//                                 .italic()
                                 .multilineTextAlignment(.center)
                                 .padding(.horizontal)
                                 .foregroundColor(.white)
                           
                           Text("LoopSpeak.")
                               .font(.title)
     //                           .monospaced()
                               .padding()
                               .foregroundColor(.white)
                               .onTapGesture {
                                   if let url = URL(string: "https://apps.apple.com/id/app/loopspeak/id6473384030") {
                                       UIApplication.shared.open(url)
                                   }
                               }
             Text("Type or paste your text, play in loop, and enjoy hands-free narration.") // Add your 30 character description here
                                 .font(.title3)
//                                 .italic()
                                 .multilineTextAlignment(.center)
                                 .padding(.horizontal)
                                 .foregroundColor(.white)
                           
                      
                           Text("TemptationTrack.")
                               .font(.title)
     //                           .monospaced()
                               .padding()
                               .foregroundColor(.white)
                               .onTapGesture {
                                   if let url = URL(string: "https://apps.apple.com/id/app/temptationtrack/id6471236988") {
                                       UIApplication.shared.open(url)
                                   }
                               }
             Text("One button to track milestones, monitor progress, stay motivated.") // Add your 30 character description here
                                 .font(.title3)
//                                 .italic()
                                 .multilineTextAlignment(.center)
                                 .padding(.horizontal)
                                 .foregroundColor(.white)


               Spacer()

               Button("Close") {
                   // Perform confirmation action
                   onConfirm()
               }
               .font(.title)
               .padding()
               .foregroundColor(.black)
               .background(Color.white)
               .cornerRadius(25.0)
               .padding()
           }
           .padding()
           .background(Color(#colorLiteral(red: 0, green: 0.5898008943, blue: 1, alpha: 1)))
           .cornerRadius(15.0)
       .padding()
        }
   }
}

    


// MARK: - Explanation View

struct ShowExplainView: View {
    var onConfirm: () -> Void

    var body: some View {
        // Explanation content...
        VStack {
            Text("Press start to begin the timer, and it will remind you every 30 seconds interval.")
                .font(.title)
                .multilineTextAlignment(.center)
 //                       .monospaced()
                .padding()
                .foregroundColor(.white)



            Spacer()

            Button("Close") {
                // Perform confirmation action
                onConfirm()
            }
            .font(.title)
            .padding()
            .foregroundColor(.black)
            .background(Color.white)
            .cornerRadius(25.0)
            .padding()
        }
        .padding()
        .background(Color(#colorLiteral(red: 0, green: 0.5898008943, blue: 1, alpha: 1)))
        .cornerRadius(15.0)
        .padding()
    }
 }
    

*/

/*

 //this work the best
import SwiftUI
import AVFoundation

class VideoCaptureDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("Video recording error: \(error.localizedDescription)")
        }
        print("Video recorded successfully: \(outputFileURL.absoluteString)")
    }
}

struct ContentView: View {
    @State private var isRecording = false
    @State private var captureSession: AVCaptureSession?
    @State private var videoOutput: AVCaptureMovieFileOutput?
    @State private var videoURL: URL?
    private let videoCaptureDelegate = VideoCaptureDelegate()

    var body: some View {
        VStack {
            Button(action: {
                if self.isRecording {
                    self.stopRecording()
                } else {
                    self.startRecording()
                }
            }) {
                Text(self.isRecording ? "Stop Recording" : "Start Recording")
            }
            Button(action: {
                self.exportVideo()
            }) {
                Text("Export Video")
            }
        }
        .onAppear {
            self.setupCamera()
        }
    }

    func setupCamera() {
        DispatchQueue.global().async {
            self.captureSession = AVCaptureSession()
            guard let captureSession = self.captureSession else { return }

            // Configure video input
            guard let videoDevice = AVCaptureDevice.default(for: .video) else {
                print("Failed to access the camera.")
                return
            }

            do {
                let videoInput = try AVCaptureDeviceInput(device: videoDevice)
                if captureSession.canAddInput(videoInput) {
                    captureSession.addInput(videoInput)
                } else {
                    print("Failed to add video input to capture session.")
                    return
                }
            } catch {
                print("Error creating video input: \(error.localizedDescription)")
                return
            }

            // Configure video output
            self.videoOutput = AVCaptureMovieFileOutput()
            guard let videoOutput = self.videoOutput else {
                print("Failed to create video output.")
                return
            }

            if captureSession.canAddOutput(videoOutput) {
                captureSession.addOutput(videoOutput)

                // Set video quality preset
                if captureSession.canSetSessionPreset(.low) {
                    captureSession.sessionPreset = .low
                } else {
                    print("Failed to set session preset.")
                    return
                }

                videoOutput.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.h264], for: videoOutput.connections.first!)
            } else {
                print("Failed to add video output to capture session.")
                return
            }

            captureSession.startRunning()
        }
    }

    func startRecording() {
        guard let videoOutput = self.videoOutput else { return }

        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let fileURL = paths[0].appendingPathComponent("video\(Date().timeIntervalSince1970).mp4")
        videoOutput.startRecording(to: fileURL, recordingDelegate: videoCaptureDelegate)
        self.isRecording = true
        self.videoURL = fileURL
    }

    func stopRecording() {
        guard let videoOutput = self.videoOutput else { return }
        videoOutput.stopRecording()
        self.isRecording = false
    }

    func exportVideo() {
        guard let videoURL = self.videoURL else { return }
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            let activityViewController = UIActivityViewController(activityItems: [videoURL], applicationActivities: nil)
            window.rootViewController?.present(activityViewController, animated: true, completion: nil)
        }
    }
}

#Preview {
    ContentView()}

*/

/*
//work but want too fix hang trhead
import SwiftUI
import AVFoundation


class VideoCaptureDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("Video recording error: \(error.localizedDescription)")
        }
        print("Video recorded successfully: \(outputFileURL.absoluteString)")
    }
}

struct ContentView: View {
    @State private var isRecording = false
    @State private var captureSession: AVCaptureSession?
    @State private var videoOutput: AVCaptureMovieFileOutput?
    @State private var videoURL: URL?
    private let videoCaptureDelegate = VideoCaptureDelegate()
    
    var body: some View {
        VStack {
            Button(action: {
                if self.isRecording {
                    self.stopRecording()
                } else {
                    self.startRecording()
                }
            }) {
                Text(self.isRecording ? "Stop Recording" : "Start Recording")
            }
            Button(action: {
                self.exportVideo()
            }) {
                Text("Export Video")
            }
        }
        .onAppear {
            self.setupCamera()
        }
    }
    
    func setupCamera() {
        self.captureSession = AVCaptureSession()
        guard let captureSession = self.captureSession else { return }
        
        // Configure video input
        guard let videoDevice = AVCaptureDevice.default(for: .video) else {
            print("Failed to access the camera.")
            return
        }
        
        do {
            let videoInput = try AVCaptureDeviceInput(device: videoDevice)
            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
            } else {
                print("Failed to add video input to capture session.")
                return
            }
        } catch {
            print("Error creating video input: \(error.localizedDescription)")
            return
        }
        
        // Configure video output
        self.videoOutput = AVCaptureMovieFileOutput()
        guard let videoOutput = self.videoOutput else {
            print("Failed to create video output.")
            return
        }
        
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
            
            // Set video quality preset
            if captureSession.canSetSessionPreset(.low) {
                captureSession.sessionPreset = .low
            } else {
                print("Failed to set session preset.")
                return
            }
            
            videoOutput.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.h264], for: videoOutput.connections.first!)
        } else {
            print("Failed to add video output to capture session.")
            return
        }
        
        captureSession.startRunning()
    }
    
    func startRecording() {
        guard let videoOutput = self.videoOutput else { return }
        
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let fileURL = paths[0].appendingPathComponent("video\(Date().timeIntervalSince1970).mp4")
        videoOutput.startRecording(to: fileURL, recordingDelegate: videoCaptureDelegate)
        self.isRecording = true
        self.videoURL = fileURL
    }
    
    func stopRecording() {
        guard let videoOutput = self.videoOutput else { return }
        videoOutput.stopRecording()
        self.isRecording = false
    }
    
    func exportVideo() {
        guard let videoURL = self.videoURL else { return }
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            let activityViewController = UIActivityViewController(activityItems: [videoURL], applicationActivities: nil)
            window.rootViewController?.present(activityViewController, animated: true, completion: nil)
        }
    }
}

#Preview {
    ContentView()}

*/

/*
this work with lower quality, but there is hang risk
import SwiftUI
import AVFoundation



class VideoCaptureDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("Video recording error: \(error.localizedDescription)")
        }
        print("Video recorded successfully: \(outputFileURL.absoluteString)")
    }
}

struct ContentView: View {
    @State private var isRecording = false
    @State private var captureSession: AVCaptureSession?
    @State private var videoOutput: AVCaptureMovieFileOutput?
    @State private var videoURL: URL?
    private let videoCaptureDelegate = VideoCaptureDelegate()

    var body: some View {
        VStack {
            Button(action: {
                if self.isRecording {
                    self.stopRecording()
                } else {
                    self.startRecording()
                }
            }) {
                Text(self.isRecording ? "Stop Recording" : "Start Recording")
            }
            Button(action: {
                self.exportVideo()
            }) {
                Text("Export Video")
            }
        }
        .onAppear {
            self.setupCamera()
        }
    }

    func setupCamera() {
        self.captureSession = AVCaptureSession()
        guard let captureSession = self.captureSession else { return }

        // Configure video input
        guard let videoDevice = AVCaptureDevice.default(for: .video) else {
            print("Failed to access the camera.")
            return
        }

        do {
            let videoInput = try AVCaptureDeviceInput(device: videoDevice)
            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
            } else {
                print("Failed to add video input to capture session.")
                return
            }
        } catch {
            print("Error creating video input: \(error.localizedDescription)")
            return
        }

        // Configure video output
        self.videoOutput = AVCaptureMovieFileOutput()
        guard let videoOutput = self.videoOutput else {
            print("Failed to create video output.")
            return
        }

        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)

            // Set video quality preset
            if captureSession.canSetSessionPreset(.low) {
                captureSession.sessionPreset = .low
            } else {
                print("Failed to set session preset.")
                return
            }

            videoOutput.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.h264], for: videoOutput.connections.first!)
        } else {
            print("Failed to add video output to capture session.")
            return
        }

        captureSession.startRunning()
    }

    func startRecording() {
        guard let videoOutput = self.videoOutput else { return }

        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let fileURL = paths[0].appendingPathComponent("video\(Date().timeIntervalSince1970).mp4")
        videoOutput.startRecording(to: fileURL, recordingDelegate: videoCaptureDelegate)
        self.isRecording = true
        self.videoURL = fileURL
    }

    func stopRecording() {
        guard let videoOutput = self.videoOutput else { return }
        videoOutput.stopRecording()
        self.isRecording = false
    }

    func exportVideo() {
        guard let videoURL = self.videoURL else { return }
        let activityViewController = UIActivityViewController(activityItems: [videoURL], applicationActivities: nil)
        UIApplication.shared.windows.first?.rootViewController?.present(activityViewController, animated: true, completion: nil)
    }
}


#Preview {
    ContentView()}
  

*/
/*
import SwiftUI
import AVFoundation
import AVKit



class VideoCaptureDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("Video recording error: \(error.localizedDescription)")
        }
        print("Video recorded successfully: \(outputFileURL.absoluteString)")
    }
}

struct ContentView: View {
    @State private var isRecording = false
    @State private var captureSession: AVCaptureSession?
    @State private var videoOutput: AVCaptureMovieFileOutput?
    @State private var videoURL: URL?
    private let videoCaptureDelegate = VideoCaptureDelegate()

    var body: some View {
        VStack {
            Button(action: {
                if self.isRecording {
                    self.stopRecording()
                } else {
                    self.startRecording()
                }
            }) {
                Text(self.isRecording ? "Stop Recording" : "Start Recording")
            }
            Button(action: {
                self.exportVideo()
            }) {
                Text("Export Video")
            }
        }
        .onAppear {
            self.setupCamera()
        }
    }

    func setupCamera() {
        self.captureSession = AVCaptureSession()
        guard let captureSession = self.captureSession else { return }

        // Configure video input
        guard let videoDevice = AVCaptureDevice.default(for: .video) else {
            print("Failed to access the camera.")
            return
        }

        do {
            let videoInput = try AVCaptureDeviceInput(device: videoDevice)
            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
            } else {
                print("Failed to add video input to capture session.")
                return
            }
        } catch {
            print("Error creating video input: \(error.localizedDescription)")
            return
        }

        // Configure video output
        self.videoOutput = AVCaptureMovieFileOutput()
        guard let videoOutput = self.videoOutput else {
            print("Failed to create video output.")
            return
        }

        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        } else {
            print("Failed to add video output to capture session.")
            return
        }

        captureSession.startRunning()
    }

    func startRecording() {
        guard let videoOutput = self.videoOutput else { return }

        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let fileURL = paths[0].appendingPathComponent("video.mp4")
        videoOutput.startRecording(to: fileURL, recordingDelegate: videoCaptureDelegate)
        self.isRecording = true
        self.videoURL = fileURL
    }

    func stopRecording() {
        guard let videoOutput = self.videoOutput else { return }
        videoOutput.stopRecording()
        self.isRecording = false
    }

    func exportVideo() {
        guard let videoURL = self.videoURL else { return }
        let activityViewController = UIActivityViewController(activityItems: [videoURL], applicationActivities: nil)
        UIApplication.shared.windows.first?.rootViewController?.present(activityViewController, animated: true, completion: nil)
    }
}


#Preview {
    ContentView()
}

*/

/*
import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")
        }
        .padding()
    }
}

#Preview {
    ContentView()
}

*/
