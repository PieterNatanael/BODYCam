//
//  ContentView.swift
//  BODYCam
//
//  Created by Pieter Yoshua Natanael on 13/04/24.
//import SwiftUI




import SwiftUI
import AVFoundation
import CoreLocation

// MARK: - Constants

/// Video quality options for recording
enum VideoQuality: Int, CaseIterable {
    case low
    case medium
    case high
    
    var description: String {
        switch self {
        case .low: return "Low (480p)"
        case .medium: return "Medium (720p)"
        case .high: return "High (1080p)"
        }
    }
    
    var preset: AVCaptureSession.Preset {
        switch self {
        case .low: return .low
        case .medium: return .medium
        case .high: return .high
        }
    }
}

// MARK: - Location Manager

/// Manages location services and provides location-related information
class LocationManager: NSObject, ObservableObject {
    // MARK: Properties
    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    
    /// Current heading in degrees
    @Published var heading: Double = 0
    /// Current altitude in meters
    @Published var altitude: Double = 0
    /// Location accuracy in meters
    @Published var accuracy: CLLocationAccuracy = 0
    /// Current coordinates
    @Published var coordinates: CLLocationCoordinate2D?
    
    // MARK: Location Details
    @Published var placeName: String = "Unknown Location"
    @Published var country: String = ""
    @Published var administrativeArea: String = ""
    @Published var subAdministrativeArea: String = ""
    @Published var locality: String = ""
    @Published var subLocality: String = ""
    @Published var thoroughfare: String = ""
    
    // MARK: Initialization
    override init() {
        super.init()
        setupLocationManager()
    }
    
    // MARK: Private Methods
    
    /// Sets up the location manager with desired accuracy and permissions
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
    }
    
    /// Performs reverse geocoding to get readable location information
    /// - Parameter location: The location to reverse geocode
    private func performReverseGeocoding(for location: CLLocation) {
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let placemark = placemarks?.first, error == nil else {
                self?.resetLocationDetails()
                return
            }
            
            DispatchQueue.main.async {
                self?.updateLocationDetails(from: placemark)
            }
        }
    }
    
    /// Updates location details from a placemark
    /// - Parameter placemark: The placemark containing location information
    private func updateLocationDetails(from placemark: CLPlacemark) {
        country = placemark.country ?? ""
        administrativeArea = placemark.administrativeArea ?? ""
        subAdministrativeArea = placemark.subAdministrativeArea ?? ""
        locality = placemark.locality ?? ""
        subLocality = placemark.subLocality ?? ""
        thoroughfare = placemark.thoroughfare ?? ""
        
        // Create formatted place name
        let nameParts = [
            placemark.subLocality,
            placemark.locality,
            placemark.subAdministrativeArea,
            placemark.administrativeArea,
            placemark.country
        ].compactMap { $0 }.filter { !$0.isEmpty }
        
        placeName = nameParts.joined(separator: ", ")
    }
    
    
    /// Resets all location details to default values
    private func resetLocationDetails() {
        DispatchQueue.main.async {
            self.placeName = "Unknown Location"
            self.country = ""
            self.administrativeArea = ""
            self.subAdministrativeArea = ""
            self.locality = ""
            self.subLocality = ""
            self.thoroughfare = ""
        }
    }
}

// MARK: - Location Manager Delegate
extension LocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        DispatchQueue.main.async {
            self.heading = newHeading.magneticHeading
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        DispatchQueue.main.async {
            self.altitude = location.altitude
            self.accuracy = location.horizontalAccuracy
            self.coordinates = location.coordinate
            self.performReverseGeocoding(for: location)
        }
    }
}

// MARK: - Video Capture Delegate

/// Handles video capture events and completion
class VideoCaptureDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput,
                   didFinishRecordingTo outputFileURL: URL,
                   from connections: [AVCaptureConnection],
                   error: Error?) {
        if let error = error {
            print("Video recording error: \(error.localizedDescription)")
        }
        print("Video recorded successfully: \(outputFileURL.absoluteString)")
    }
}

// MARK: - Main View

/// Main view for the body camera interface
struct ContentView: View {
    // MARK: Properties
    
    /// Video capture related properties
    @State private var isRecording = false
    @State private var captureSession: AVCaptureSession?
    @State private var videoOutput: AVCaptureMovieFileOutput?
    @State private var videoURL: URL?
    private let videoCaptureDelegate = VideoCaptureDelegate()
    
    /// UI State properties
    @State private var showCompass = false
    @State private var showExplain = false
    @State private var selectedQuality = VideoQuality.low
    
    /// Compass properties
    @StateObject private var locationManager = LocationManager()
    
    // MARK: Body
    var body: some View {
        ZStack {
            
            ZStack {
                // Background
                Image("pattern1")
                    .resizable()
                    .ignoresSafeArea()
                LinearGradient(colors: [Color(#colorLiteral(red: 0, green: 0, blue: 0, alpha: 1)), Color(#colorLiteral(red: 0.4756349325, green: 0.4756467342, blue: 0.4756404161, alpha: 1))],
                               startPoint: .top,
                               endPoint: .bottom)
                .opacity(0.8)
                .ignoresSafeArea()
            }
            
            VStack {
                // Top toolbar
                toolbarView
                
                Spacer()
                
                //compass
                ZStack {
                    CompassRoseView(heading: locationManager.heading)
                }
                
                Spacer()
                
                // Control buttons
                controlButtons
                Spacer()
            }
        }
        .sheet(isPresented: $showCompass) {
            showCompassView(onConfirm: {
                showCompass = false
            })
        }
        .sheet(isPresented: $showExplain, onDismiss: {
            UserDefaults.standard.set(selectedQuality.rawValue, forKey: "SelectedVideoQuality")
            updateCaptureSessionPreset()
        }) {
            ShowExplainView(captureSession: $captureSession,
                           selectedQuality: $selectedQuality,
                           isPresented: $showExplain)
        }
        .onAppear {
            setupCaptureSession()
            loadSavedQuality()
        }
    }
    
    // MARK: UI Components
    
    /// Top toolbar with compass and help buttons
    private var toolbarView: some View {
        HStack {
            Button(action: { showCompass = true }) {
                Image(systemName: "location.north.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(Color(#colorLiteral(red: 0.8039215803, green: 0.8039215803, blue: 0.8039215803, alpha: 1)))
                    .padding()
            }
            
            Spacer()
            
            Button(action: { showExplain = true }) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(Color(#colorLiteral(red: 0.8039215803, green: 0.8039215803, blue: 0.8039215803, alpha: 1)))
                    .padding()
            }
        }
    }
    
    /// Control buttons for recording and export
    private var controlButtons: some View {
        VStack {
            // Record button
            Button(action: { isRecording ? stopRecording() : startRecording() }) {
                Text(isRecording ? "Stop " : "Start")
                    .font(.title2)
                    .padding()
                    .frame(width: 233)
                    .background(isRecording ?    RadialGradient(gradient: Gradient(colors: [Color(#colorLiteral(red: 0.2605174184, green: 0.2605243921, blue: 0.260520637, alpha: 1)),  Color(#colorLiteral(red: 0.4756349325, green: 0.4756467342, blue: 0.4756404161, alpha: 1))]),
                                                                center:.topLeading,
                                                                startRadius: 10,
                                                                endRadius: 400) :    RadialGradient(gradient: Gradient(colors: [Color(#colorLiteral(red: 1, green: 1, blue: 1, alpha: 1)),  Color(#colorLiteral(red: 0.8039215803, green: 0.8039215803, blue: 0.8039215803, alpha: 1))]),
                                                                                                                                                  center:.topLeading,
                                                                                                                                                  startRadius: 10,
                                                                                                                                                  endRadius: 400))
                    .cornerRadius(25)
                    .shadow(color: Color.black.opacity(0.4), radius: 10, x: 5, y: 5) // Shadow for depth
                    .overlay(
                        RoundedRectangle(cornerRadius: 25)
                            .stroke(Color.black.opacity(0.6), lineWidth: 2) // Optional border
                    )
                    .foregroundColor(.black)
            }
            .padding(.bottom, 18)
            
            // Export button
            Button(action: { exportVideo() }) {
                Text("Export")
                    .font(.title2)
                    .padding()
                    .frame(width: 233)
                    .background(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                Color(#colorLiteral(red: 0.2605174184, green: 0.2605243921, blue: 0.260520637, alpha: 1)),
                                Color(#colorLiteral(red: 0.4756349325, green: 0.4756467342, blue: 0.4756404161, alpha: 1))
                            ]),
                            center: .topLeading,
                            startRadius: 10,
                            endRadius: 400
                        )
                    )
                    .cornerRadius(25)
                    .shadow(color: Color.black.opacity(0.4), radius: 10, x: 5, y: 5) // Shadow for depth
                    .overlay(
                        RoundedRectangle(cornerRadius: 25)
                            .stroke(Color.black.opacity(0.8), lineWidth: 2) // Optional border
                    )
                    .foregroundColor(.white)
            }
        }
        .padding()
    }
    
    // MARK: Setup Methods
    
    /// Sets up the capture session with the selected quality
    private func setupCaptureSession() {
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
    
    /// Loads the saved quality setting from UserDefaults
    private func loadSavedQuality() {
        if let savedQuality = UserDefaults.standard.object(forKey: "SelectedVideoQuality") as? Int,
           let quality = VideoQuality(rawValue: savedQuality) {
            selectedQuality = quality
        }
    }
    
    /// Updates the capture session preset based on selected quality
    private func updateCaptureSessionPreset() {
        DispatchQueue.main.async {
            captureSession?.beginConfiguration()
            captureSession?.sessionPreset = selectedQuality.preset
            captureSession?.commitConfiguration()
        }
    }
    
    // MARK: Recording Methods
    
    /// Starts video recording
    private func startRecording() {
        guard let videoOutput = self.videoOutput else {
            print("Video output is nil.")
            return
        }

        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let fileURL = paths[0].appendingPathComponent("video\(Date().timeIntervalSince1970).mp4")
        
        do {
            try videoOutput.startRecording(to: fileURL, recordingDelegate: videoCaptureDelegate)
            self.isRecording = true
            self.videoURL = fileURL
        } catch {
            print("Error starting recording: \(error.localizedDescription)")
        }
    }

    /// Stops video recording
    private func stopRecording() {
        guard let videoOutput = self.videoOutput else {
            print("Video output is nil.")
            return
        }

        if videoOutput.isRecording {
            videoOutput.stopRecording()
            self.isRecording = false
        }
    }

    /// Exports the recorded video
    private func exportVideo() {
        guard let videoURL = self.videoURL else {
            print("Video URL is nil.")
            return
        }

        let activityViewController = UIActivityViewController(activityItems: [videoURL], applicationActivities: nil)
        
        // Get the current scene's window and root view controller
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(activityViewController, animated: true, completion: nil)
        }
    }
}

// MARK: - Compass View

struct showCompassView: View {
    var onConfirm: () -> Void
    @StateObject private var locationManager = LocationManager()
    @State private var isCopied = false
    
    var body: some View {
        ZStack {
       
            ZStack {
                // Background Gradient
                Image("pattern1")
                    .resizable()
                    .ignoresSafeArea()
                LinearGradient(colors: [Color(#colorLiteral(red: 0.2605174184, green: 0.2605243921, blue: 0.260520637, alpha: 1)), Color(#colorLiteral(red: 0.4756349325, green: 0.4756467342, blue: 0.4756404161, alpha: 1))],
                               startPoint: .top,
                               endPoint: .bottom)
                .opacity(0.7)
                .ignoresSafeArea()
            }
            
            VStack {
                Spacer()
                ZStack {
                    CompassRoseView(heading: locationManager.heading)
                }
//                .rotationEffect(Angle(degrees: locationManager.heading))
                
                Spacer()
                
                Text("Current Heading: \(Int(locationManager.heading))°")
                    .padding()
                    .foregroundColor(Color(#colorLiteral(red: 0.8039215803, green: 0.8039215803, blue: 0.8039215803, alpha: 1)))
                
                VStack(alignment: .leading, spacing: 10) {
                    // Display place name
                    HStack {
                        Image(systemName: "mappin.circle")
                        Text(locationManager.placeName)
                            .fontWeight(.bold)
                            .foregroundColor(Color(#colorLiteral(red: 0.8039215803, green: 0.8039215803, blue: 0.8039215803, alpha: 1)))
                    }
                    
                    HStack {
                        Image(systemName: "arrow.up.and.down.circle")
                        Text("Altitude: \(String(format: "%.1f", locationManager.altitude)) m")
                            .foregroundColor(Color(#colorLiteral(red: 0.8039215803, green: 0.8039215803, blue: 0.8039215803, alpha: 1)))
                    }
                    
                    // Coordinates Display
                    if let coords = locationManager.coordinates {
                        HStack {
                            Image(systemName: "map")
                            Text("Coordinates:")
                                .foregroundColor(Color(#colorLiteral(red: 0.8039215803, green: 0.8039215803, blue: 0.8039215803, alpha: 1)))
                            Text(coordinatesString(coords))
                                .fontWeight(.bold)
                                .foregroundColor(Color(#colorLiteral(red: 0.8039215803, green: 0.8039215803, blue: 0.8039215803, alpha: 1)))
                        }
                    }
                    
                    HStack {
                        Image(systemName: "location.circle")
                        Text("Accuracy: \(String(format: "%.1f", locationManager.accuracy)) m")
                            .foregroundColor(Color(#colorLiteral(red: 0.8039215803, green: 0.8039215803, blue: 0.8039215803, alpha: 1)))
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                
                Spacer()
          
                // Close button
                Button("Close") {
                    onConfirm()
                }
                .font(.title)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(#colorLiteral(red: 0.2549019754, green: 0.2745098174, blue: 0.3019607961, alpha: 1)),
                            Color(#colorLiteral(red: 0.3921568999, green: 0.4117647111, blue: 0.4352941215, alpha: 1))
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .foregroundColor(.white)
                .cornerRadius(10)
                .shadow(color: Color.black.opacity(0.4), radius: 8, x: 4, y: 4) // Shadow for depth
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.black.opacity(0.8), lineWidth: 1) // Optional border for refinement
                )
                .padding(.vertical, 10)
              
              
            }
            .padding()
            .cornerRadius(15.0)
            .padding()
        }
    }
    
    // Format coordinates for easy sharing
    func coordinatesString(_ coordinate: CLLocationCoordinate2D) -> String {
        return String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude)
    }
    
    // Copy location information
    func copyLocationInformation() {
        guard let coords = locationManager.coordinates else { return }
        
        let locationInfo = """
        Location: \(locationManager.placeName)
        Heading: \(Int(locationManager.heading))°
        Altitude: \(String(format: "%.1f", locationManager.altitude)) m
        Coordinates: \(coordinatesString(coords))
        Accuracy: \(String(format: "%.1f", locationManager.accuracy)) m
        
        Detailed Location:
        Country: \(locationManager.country)
        Administrative Area: \(locationManager.administrativeArea)
        Sub-Administrative Area: \(locationManager.subAdministrativeArea)
        Locality: \(locationManager.locality)
        Sub-Locality: \(locationManager.subLocality)
        Thoroughfare: \(locationManager.thoroughfare)
        """
        
        UIPasteboard.general.string = locationInfo
        isCopied = true
        
        // Reset copied state after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isCopied = false
        }
    }
    
    var accuracyColor: Color {
        switch locationManager.accuracy {
        case ..<0:
            return .red  // Invalid location
        case 0..<10:
            return .green  // Very accurate
        case 10..<50:
            return .yellow  // Moderate accuracy
        default:
            return .red  // Poor accuracy
        }
    }
}

// MARK: - Compass Components

struct CompassRoseView: View {
    let heading: Double
    var size: CGFloat = 250
    var arrowSize: CGFloat = 99
    var strokeWidth: CGFloat = 33
    var strokeColor: Color = Color(#colorLiteral(red: 0.721568644, green: 0.8862745166, blue: 0.5921568871, alpha: 1)).opacity(0.85)
    var arrowColor: Color = Color(#colorLiteral(red: 1, green: 0.8323456645, blue: 0.4732058644, alpha: 1))
    
    var body: some View {
        ZStack {
            // Compass background circle
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [
                                Color(#colorLiteral(red: 0, green: 0, blue: 0, alpha: 1)),
                                Color(#colorLiteral(red: 0.501960814, green: 0.501960814, blue: 0.501960814, alpha: 1))
                            ]),
                            center: .topLeading,
                            startRadius: 10,
                            endRadius: 400
                        )
                    )
                    .frame(width: size, height: size)
                    .shadow(color: Color.black.opacity(0.5), radius: 15, x: 10, y: 10) // Outer shadow
                    .overlay(
                        Circle()
                            .stroke(Color.black.opacity(0.5), lineWidth: 2) // Optional subtle border
                    )
                    .overlay(
                        Circle()
                            .stroke(
                                RadialGradient(
                                    gradient: Gradient(colors: [
                                        Color.white.opacity(0.5),
                                        Color.clear
                                    ]),
                                    center: .center,
                                    startRadius: 1,
                                    endRadius: size / 2
                                ),
                                lineWidth: strokeWidth
                            ) // Inner glow effect
                    )

                Circle()
                    .stroke(strokeColor, lineWidth: strokeWidth)
                    .frame(width: size, height: size)
            }
                
            
            // Compass Rose
            Image(systemName: "location.north.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: arrowSize, height: arrowSize)
                .foregroundColor(arrowColor)
                .rotationEffect(Angle(degrees: -heading))
            
            // Compass markings
            ForEach(0..<360, id: \.self) { degree in
                if degree % 45 == 0 {
                    CompassMarkView(degree: Double(degree), currentHeading: heading)
                }
            }
        }
        .rotationEffect(Angle(degrees: heading))
    }
}

// MARK: - Explanation View

struct ShowExplainView: View {
    @Binding var captureSession: AVCaptureSession?
    @Binding var selectedQuality: VideoQuality // Add this line
    @Binding var isPresented: Bool
    @StateObject private var locationManager = LocationManager()

    var body: some View {
        ZStack {
            
            
                // Background Gradient
                Image("pattern1")
                    .resizable()
                    .ignoresSafeArea()
                LinearGradient(colors: [Color(#colorLiteral(red: 0.2605174184, green: 0.2605243921, blue: 0.260520637, alpha: 1)), Color(#colorLiteral(red: 0.4756349325, green: 0.4756467342, blue: 0.4756404161, alpha: 1))],
                               startPoint: .top,
                               endPoint: .bottom)
                .opacity(0.7)
                .ignoresSafeArea()
            
            ScrollView {
                ZStack {
                    
                    
                    
                    VStack {
                        
                        // Video Quality Picker
                        HStack {
                            Text("Video Quality")
                                .font(.title.bold())
                                .foregroundColor(Color(#colorLiteral(red: 0.8039215803, green: 0.8039215803, blue: 0.8039215803, alpha: 1)))
                                .multilineTextAlignment(.leading)
                            Spacer()
                        }
                        Picker("Video Quality", selection: $selectedQuality) {
                            Text("Low").tag(VideoQuality.low)
                            Text("Medium").tag(VideoQuality.medium)
                            Text("High").tag(VideoQuality.high)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .padding()
                        .foregroundColor(.white)
                        
                        
                        
                        
                        
                        
                        
                        
                        
                        // App Functionality Explanation
                        HStack{
                            Text("App Functionality")
                                .font(.title.bold())
                                .foregroundColor(Color(#colorLiteral(red: 0.8039215803, green: 0.8039215803, blue: 0.8039215803, alpha: 1)))
                            
                            //make it bigger
                                .font(.title3)
                            
                            
                            
                            
                            
                            
                        }
                        Text("""
                        • Press start to begin recording video.
                        • Press stop to stop recording.
                        • Press export to export the file.
                        • The app overwrites previous data when the start button is pressed again.
                        • The app cannot run in the background; auto-lock should be set to 'Never' to avoid turning off due to inactivity.
                        • Video quality should not be changed during recording to avoid stopping the record session.
                        """)
                        .font(.title3)
                        .foregroundColor(Color(#colorLiteral(red: 0.8039215803, green: 0.8039215803, blue: 0.8039215803, alpha: 1)))
                        .multilineTextAlignment(.leading)
                        .padding()
                        
                        HStack {
                            Text("BODYCam Outdoor Gear is developed by Three Dollar.")
                                .font(.title3.bold())
                                .foregroundColor(Color(#colorLiteral(red: 0.8039215803, green: 0.8039215803, blue: 0.8039215803, alpha: 1)))
                            Spacer()
                            
                        }
                        
                        
                        HStack{
                            Text("App for you")
                                .font(.title.bold())
                                .foregroundColor(Color(#colorLiteral(red: 0.8039215803, green: 0.8039215803, blue: 0.8039215803, alpha: 1)))
                            
                            
                            Spacer()
                        }
                        
                        // App Cards
                        VStack {
                            
                            
                            
                            
                            AppCardView(imageName: "timetell", appName: "TimeTell", appDescription: "Announce the time every 30 seconds, no more guessing and checking your watch, for time-sensitive tasks.", appURL: "https://apps.apple.com/id/app/loopspeak/id6473384030")
                            Divider().background(Color.gray)
                            
                            
                            
                            AppCardView(imageName: "insomnia", appName: "Insomnia Sheep", appDescription: "The Ultimate Sleep App you need.", appURL: "https://apps.apple.com/id/app/insomnia-sheep/id6479727431")
                            Divider().background(Color.gray)
                            
                            
                            
                            AppCardView(imageName: "iprogram", appName: "iProgramMe", appDescription: "Custom affirmations, schedule notifications, stay inspired daily.", appURL: "https://apps.apple.com/id/app/iprogramme/id6470770935")
                            Divider().background(Color.gray)
                            
                            
                            
                        }
                        
                        
                        
                        Button("Close") {
                            // Perform confirmation action
                            updateCaptureSessionPreset()
                            isPresented = false
                        }
                        .font(.title)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(#colorLiteral(red: 0.2549019754, green: 0.2745098174, blue: 0.3019607961, alpha: 1)),
                                    Color(#colorLiteral(red: 0.3921568999, green: 0.4117647111, blue: 0.4352941215, alpha: 1))
                                ]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .shadow(color: Color.black.opacity(0.4), radius: 8, x: 4, y: 4) // Shadow for depth
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.black.opacity(0.8), lineWidth: 1) // Optional border for refinement
                        )
                        .padding(.vertical, 10)
                        
                    }
                    .padding()
                    .cornerRadius(15.0)
                    .padding()
                    
                    Spacer()
                }
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


// MARK: - App Card View

struct AppCardView: View {
    var imageName: String
    var appName: String
    var appDescription: String
    var appURL: String
    
    var body: some View {
        HStack {
            Image(imageName)
                .resizable()
                .scaledToFill()
                .frame(width: 60, height: 60)
                .cornerRadius(7)
            
            VStack(alignment: .leading, content: {
                Text(appName)
                    .font(.title3)
                    .foregroundColor(Color(#colorLiteral(red: 0.6000000238, green: 0.6000000238, blue: 0.6000000238, alpha: 1)))
                Text(appDescription)
                    .font(.caption)
                    .foregroundColor(Color(#colorLiteral(red: 0.6000000238, green: 0.6000000238, blue: 0.6000000238, alpha: 1)))
            })
            .frame(alignment: .leading)
            
            Spacer()
            Button(action: {
                if let url = URL(string: appURL) {
                    UIApplication.shared.open(url)
                }
            }) {
                Text("Try")
                    .font(.headline)
                    .padding()
                    .frame(minWidth: 100) // Ensures consistent size
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.blue.opacity(0.8),
                                Color.blue.opacity(1.0)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .foregroundColor(.white)
                    .cornerRadius(13)
                    .shadow(color: Color.black.opacity(0.3), radius: 6, x: 3, y: 3) // Shadow for 3D effect
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.black.opacity(0.8), lineWidth: 1) // Optional border
                    )
            }
        }
    }
}

// MARK: - Compass Mark View

struct CompassMarkView: View {
    let degree: Double
    let currentHeading: Double

    var directionText: String {
        switch degree {
        case 0: return "N"
        case 45: return "NE"
        case 90: return "E"
        case 135: return "SE"
        case 180: return "S"
        case 225: return "SW"
        case 270: return "W"
        case 315: return "NW"
        default: return ""
        }
    }

    var body: some View {
        VStack {
            Text(directionText)
                .font(.caption)
                .rotationEffect(Angle(degrees: -degree + currentHeading))
        }
        .offset(y: -125)
        .rotationEffect(Angle(degrees: degree))
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

//kerjaan di branching
//try branching, kerjaan di branching

/*

 //Previous app release

//works, but want to improve style and code quality


import SwiftUI
import AVFoundation
import CoreLocation

class LocationManager: NSObject, ObservableObject {
    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    
    @Published var heading: Double = 0
    @Published var altitude: Double = 0
    @Published var accuracy: CLLocationAccuracy = 0
    @Published var coordinates: CLLocationCoordinate2D?
    
    // New published properties for location details
    @Published var placeName: String = "Unknown Location"
    @Published var country: String = ""
    @Published var administrativeArea: String = ""
    @Published var subAdministrativeArea: String = ""
    @Published var locality: String = ""
    @Published var subLocality: String = ""
    @Published var thoroughfare: String = ""
    
    override init() {
        super.init()
        setupLocationManager()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
    }
    
    private func performReverseGeocoding(for location: CLLocation) {
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let placemark = placemarks?.first, error == nil else {
                self?.resetLocationDetails()
                return
            }
            
            DispatchQueue.main.async {
                // Update location details
                self?.country = placemark.country ?? ""
                self?.administrativeArea = placemark.administrativeArea ?? ""
                self?.subAdministrativeArea = placemark.subAdministrativeArea ?? ""
                self?.locality = placemark.locality ?? ""
                self?.subLocality = placemark.subLocality ?? ""
                self?.thoroughfare = placemark.thoroughfare ?? ""
                
                // Create a formatted place name
                var nameParts = [String]()
                if let subLocality = placemark.subLocality, !subLocality.isEmpty {
                    nameParts.append(subLocality)
                }
                if let locality = placemark.locality, !locality.isEmpty {
                    nameParts.append(locality)
                }
                if let subAdministrative = placemark.subAdministrativeArea, !subAdministrative.isEmpty {
                    nameParts.append(subAdministrative)
                }
                if let administrative = placemark.administrativeArea, !administrative.isEmpty {
                    nameParts.append(administrative)
                }
                if let country = placemark.country, !country.isEmpty {
                    nameParts.append(country)
                }
                
                self?.placeName = nameParts.joined(separator: ", ")
            }
        }
    }
    
    private func resetLocationDetails() {
        DispatchQueue.main.async {
            self.placeName = "Unknown Location"
            self.country = ""
            self.administrativeArea = ""
            self.subAdministrativeArea = ""
            self.locality = ""
            self.subLocality = ""
            self.thoroughfare = ""
        }
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        DispatchQueue.main.async {
            self.heading = newHeading.magneticHeading
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        DispatchQueue.main.async {
            self.altitude = location.altitude
            self.accuracy = location.horizontalAccuracy
            self.coordinates = location.coordinate
            
            // Perform reverse geocoding
            self.performReverseGeocoding(for: location)
        }
    }
}




// Delegate for handling video capture events
class VideoCaptureDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("Video recording error: \(error.localizedDescription)")
        }
        print("Video recorded successfully: \(outputFileURL.absoluteString)")
    }
}

struct ContentView: View {
    // State variables
    @State private var isRecording = false
    @State private var captureSession: AVCaptureSession?
    @State private var videoOutput: AVCaptureMovieFileOutput?
    @State private var videoURL: URL?
    private let videoCaptureDelegate = VideoCaptureDelegate()
  
    @State private var showCompass = false
//    @State private var showCompass: Bool = false
    @State private var showExplain: Bool = false
    @State private var selectedQuality = VideoQuality.low // Default quality selection
    
    var body: some View {
        ZStack {
            // Background Gradient
            LinearGradient(colors: [Color(#colorLiteral(red: 0.5738074183, green: 0.5655357838, blue: 0, alpha: 1)),.clear], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack {
                HStack{
                    
                    Button(action: {
                        showCompass = true
                    }) {
                        Image(systemName: "location.north.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white)
                            .padding()
                    }
                 
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
                Spacer()
                
                
                
                
                // Start/Stop Recording Button
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
                .background(isRecording ? Color(#colorLiteral(red: 1, green: 0.8323456645, blue: 0.4732058644, alpha: 1)) : Color.white )
                .cornerRadius(25)
                .foregroundColor(isRecording ? Color.black : Color.black)
                .padding(.bottom, 18)
                
                // Export Button
                Button(action: {
                    self.exportVideo()
                }) {
                    Text("Export")
                }
                .font(.title2)
                .padding()
                .frame(width: 233)
                .background( Color(#colorLiteral(red: 0.5738074183, green: 0.5655357838, blue: 0, alpha: 1)) )
                .cornerRadius(25)
                .foregroundColor(.white)
                Spacer()
            }
            .onAppear {
                self.setupCamera()
            }
            .sheet(isPresented: $showCompass) {
                showCompassView(onConfirm: {
                    showCompass = false
                })
            }
            
//            .sheet(isPresented: $showCompass, onDismiss: {
//                UserDefaults.standard.set(selectedQuality.rawValue, forKey: "SelectedVideoQuality")
//                updateCaptureSessionPreset()
//            }) {
//                showCompassView()
//            }
           
            .sheet(isPresented: $showExplain, onDismiss: {
                UserDefaults.standard.set(selectedQuality.rawValue, forKey: "SelectedVideoQuality")
                updateCaptureSessionPreset()
            }) {
                ShowExplainView(captureSession: $captureSession, selectedQuality: $selectedQuality, isPresented: $showExplain)
            }
        }
    }
    
    // Setup the camera session
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
    
    // Start video recording
    func startRecording() {
        guard let videoOutput = self.videoOutput else {
            print("Video output is nil.")
            return
        }

        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let fileURL = paths[0].appendingPathComponent("video\(Date().timeIntervalSince1970).mp4")
        
        do {
            try videoOutput.startRecording(to: fileURL, recordingDelegate: videoCaptureDelegate)
            self.isRecording = true
            self.videoURL = fileURL
        } catch {
            print("Error starting recording: \(error.localizedDescription)")
        }
    }

    // Stop video recording
    func stopRecording() {
        guard let videoOutput = self.videoOutput else {
            print("Video output is nil.")
            return
        }

        if videoOutput.isRecording {
            videoOutput.stopRecording()
            self.isRecording = false
        }
    }

    // Export video//ganti solution agar tidak crash

    func exportVideo() {
        guard let videoURL = self.videoURL else {
            print("Video URL is nil.")
            return
        }

        let activityViewController = UIActivityViewController(activityItems: [videoURL], applicationActivities: nil)
        
        // Get the current scene's window and root view controller
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(activityViewController, animated: true, completion: nil)
        }
    }
    
    // Update capture session preset based on selected video quality
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






struct AppCardView: View {
    var imageName: String
    var appName: String
    var appDescription: String
    var appURL: String
    
    var body: some View {
        HStack {
            Image(imageName)
                .resizable()
                .scaledToFill()
                .frame(width: 60, height: 60)
                .cornerRadius(7)
            
            VStack(alignment: .leading, content: {
                Text(appName)
                    .font(.title3)
                Text(appDescription)
                    .font(.caption)
            })
            .frame(alignment: .leading)
            
            Spacer()
            Button(action: {
                if let url = URL(string: appURL) {
                    UIApplication.shared.open(url)
                }
            }) {
                Text("Try")
                    .font(.headline)
                    .padding()
                    .foregroundColor(.white)
                    .background(Color.blue)
                    .cornerRadius(10)
            }
        }
    }
}


// MARK: - Compass View

struct showCompassView: View {
    var onConfirm: () -> Void
    @StateObject private var locationManager = LocationManager()
    @State private var isCopied = false
    
    var body: some View {
        ZStack {
            // Background Gradient
            LinearGradient(colors: [Color(#colorLiteral(red: 0.5738074183, green: 0.5655357838, blue: 0, alpha: 1)),.clear], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack {
                Spacer()
                ZStack {
                    // Compass background circle
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                        .frame(width: 250, height: 250)
                    
                    // Compass Rose
                    Image(systemName: "arrow.up")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 30, height: 30)
                        .foregroundColor(.red)
                        .rotationEffect(Angle(degrees: -locationManager.heading))
                    
                    // Compass markings
                    ForEach(0..<360, id: \.self) { degree in
                        if degree % 45 == 0 {
                            CompassMarkView(degree: Double(degree), currentHeading: locationManager.heading)
                        }
                    }
                }
                .rotationEffect(Angle(degrees: locationManager.heading))
                
                Spacer()
                
                Text("Current Heading: \(Int(locationManager.heading))°")
                    .padding()
                
                VStack(alignment: .leading, spacing: 10) {
                    // Display place name
                    HStack {
                        Image(systemName: "mappin.circle")
                        Text(locationManager.placeName)
                            .fontWeight(.bold)
                    }
                    
                    HStack {
                        Image(systemName: "arrow.up.and.down.circle")
                        Text("Altitude: \(String(format: "%.1f", locationManager.altitude)) m")
                    }
                    
                    // Coordinates Display
                    if let coords = locationManager.coordinates {
                        HStack {
                            Image(systemName: "map")
                            Text("Coordinates:")
                            Text(coordinatesString(coords))
                                .fontWeight(.bold)
                        }
                    }
                    
                    HStack {
                        Image(systemName: "location.circle")
                        Text("Accuracy: \(String(format: "%.1f", locationManager.accuracy)) m")
                            .foregroundColor(accuracyColor)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                
                Spacer()
          
                // Close button
                Button("Close") {
                    onConfirm()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(#colorLiteral(red: 0.5738074183, green: 0.5655357838, blue: 0, alpha: 1)))
                .foregroundColor(.white)
                .font(.title3.bold())
                .cornerRadius(10)
                .padding()
              
                // Large Copy Button
//                Button(action: {
//                    copyLocationInformation()
//                }) {
//                    HStack {
//                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
//                        Text(isCopied ? "Copied!" : "Copy Location Details")
//                    }
//                    .frame(maxWidth: .infinity)
//                    .padding()
//                    .background(isCopied ? Color.blue : Color(#colorLiteral(red: 0.5738074183, green: 0.5655357838, blue: 0, alpha: 1)))
//                    .foregroundColor(.black)
//                    .cornerRadius(10)
//                    .font(.headline)
//                }
//                .padding()
            }
        }
    }
    
    // Format coordinates for easy sharing
    func coordinatesString(_ coordinate: CLLocationCoordinate2D) -> String {
        return String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude)
    }
    
    // Copy location information
    func copyLocationInformation() {
        guard let coords = locationManager.coordinates else { return }
        
        let locationInfo = """
        Location: \(locationManager.placeName)
        Heading: \(Int(locationManager.heading))°
        Altitude: \(String(format: "%.1f", locationManager.altitude)) m
        Coordinates: \(coordinatesString(coords))
        Accuracy: \(String(format: "%.1f", locationManager.accuracy)) m
        
        Detailed Location:
        Country: \(locationManager.country)
        Administrative Area: \(locationManager.administrativeArea)
        Sub-Administrative Area: \(locationManager.subAdministrativeArea)
        Locality: \(locationManager.locality)
        Sub-Locality: \(locationManager.subLocality)
        Thoroughfare: \(locationManager.thoroughfare)
        """
        
        UIPasteboard.general.string = locationInfo
        isCopied = true
        
        // Reset copied state after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isCopied = false
        }
    }
    
    var accuracyColor: Color {
        switch locationManager.accuracy {
        case ..<0:
            return .red  // Invalid location
        case 0..<10:
            return .green  // Very accurate
        case 10..<50:
            return .yellow  // Moderate accuracy
        default:
            return .red  // Poor accuracy
        }
    }
}

// MARK: - Explanation View

struct ShowExplainView: View {
    @Binding var captureSession: AVCaptureSession?
    @Binding var selectedQuality: VideoQuality // Add this line
    @Binding var isPresented: Bool
    @StateObject private var locationManager = LocationManager()

    var body: some View {
        ScrollView {
            ZStack {
                LinearGradient(colors: [Color(#colorLiteral(red: 0.5738074183, green: 0.5655357838, blue: 0, alpha: 1)),.clear], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                VStack {
                    
                    // Video Quality Picker
                    HStack {
                        Text("Video Quality")
                            .font(.title.bold())
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                    Picker("Video Quality", selection: $selectedQuality) {
                        Text("Low").tag(VideoQuality.low)
                        Text("Medium").tag(VideoQuality.medium)
                        Text("High").tag(VideoQuality.high)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding()
                    .foregroundColor(.white)
                    
                    
                    Spacer()
            
                  
              
                    
                    
                    
                    // App Functionality Explanation
                    HStack{
                        Text("App Functionality")
                            .font(.title.bold())
                        
                        //make it bigger
                            .font(.title3)
                        
                        
                        
                        
                        
                        
                        Spacer()
                    }
                    Text("""
                    • Press start to begin recording video.
                    • Press stop to stop recording.
                    • Press export to export the file.
                    • The app overwrites previous data when the start button is pressed again.
                    • The app cannot run in the background; auto-lock should be set to 'Never' to avoid turning off due to inactivity.
                    • Video quality should not be changed during recording to avoid stopping the record session.
                    """)
                    .font(.title3)
                    .multilineTextAlignment(.leading)
                    .padding()
                    
                    HStack {
                        Text("BODYCam is developed by Three Dollar.")
                            .font(.title3.bold())
                        Spacer()
                        
                    }
                    Spacer()
                    
                    HStack{
                        Text("App for you")
                            .font(.title.bold())
                        
                        
                        Spacer()
                    }
                    
                    // App Cards
                    VStack {
                        
                        
                        
                        //                    Divider().background(Color.gray)
                        //                    AppCardView(imageName: "sos", appName: "SOS Light", appDescription: "SOS Light is designed to maximize the chances of getting help in emergency situations.", appURL: "https://apps.apple.com/app/s0s-light/id6504213303")
                        //                    Divider().background(Color.gray)
                        //
                        //
                        
                        //                    AppCardView(imageName: "temptation", appName: "TemptationTrack", appDescription: "One button to track milestones, monitor progress, stay motivated.", appURL: "https://apps.apple.com/id/app/temptationtrack/id6471236988")
                        //                    Divider().background(Color.gray)
                        //                    // Add more AppCardViews here if needed
                        //                    // App Data
                        //
                        
                        AppCardView(imageName: "timetell", appName: "TimeTell", appDescription: "Announce the time every 30 seconds, no more guessing and checking your watch, for time-sensitive tasks.", appURL: "https://apps.apple.com/id/app/loopspeak/id6473384030")
                        Divider().background(Color.gray)
                        
                        //                    AppCardView(imageName: "BST", appName: "Blink Screen Time", appDescription: "Using screens can reduce your blink rate to just 6 blinks per minute, leading to dry eyes and eye strain. Our app helps you maintain a healthy blink rate to prevent these issues and keep your eyes comfortable.", appURL: "https://apps.apple.com/id/app/blink-screen-time/id6587551095")
                        //                    Divider().background(Color.gray)
                        
                        //                    AppCardView(imageName: "SingLoop", appName: "Sing LOOP", appDescription: "Record your voice effortlessly, and play it back in a loop.", appURL: "https://apps.apple.com/id/app/sing-l00p/id6480459464")
                        //                    Divider().background(Color.gray)
                        //
                        //                    AppCardView(imageName: "loopspeak", appName: "LOOPSpeak", appDescription: "Type or paste your text, play in loop, and enjoy hands-free narration.", appURL: "https://apps.apple.com/id/app/loopspeak/id6473384030")
                        //                    Divider().background(Color.gray)
                        
                        AppCardView(imageName: "insomnia", appName: "Insomnia Sheep", appDescription: "The Ultimate Sleep App you need.", appURL: "https://apps.apple.com/id/app/insomnia-sheep/id6479727431")
                        Divider().background(Color.gray)
                        
                        //                    AppCardView(imageName: "dryeye", appName: "Dry Eye Read", appDescription: "The go-to solution for a comfortable reading experience, by adjusting font size and color to suit your reading experience.", appURL: "https://apps.apple.com/id/app/dry-eye-read/id6474282023")
                        //                    Divider().background(Color.gray)
                        
                        AppCardView(imageName: "iprogram", appName: "iProgramMe", appDescription: "Custom affirmations, schedule notifications, stay inspired daily.", appURL: "https://apps.apple.com/id/app/iprogramme/id6470770935")
                        Divider().background(Color.gray)
                        
                        //                    AppCardView(imageName: "worry", appName: "Worry Bin", appDescription: "A place for worry.", appURL: "https://apps.apple.com/id/app/worry-bin/id6498626727")
                        //                    Divider().background(Color.gray)
                        
                    }
                    Spacer()
                    
                    
                    
                    Button("Close") {
                        // Perform confirmation action
                        updateCaptureSessionPreset()
                        isPresented = false
                    }
                    .font(.title)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(#colorLiteral(red: 0.5738074183, green: 0.5655357838, blue: 0, alpha: 1)))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .padding(.vertical, 10)
                }
                .padding()
                .cornerRadius(15.0)
                .padding()
            }
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






// Compass marking view for cardinal and ordinal directions
struct CompassMarkView: View {
let degree: Double
let currentHeading: Double

var directionText: String {
    switch degree {
    case 0: return "N"
    case 45: return "NE"
    case 90: return "E"
    case 135: return "SE"
    case 180: return "S"
    case 225: return "SW"
    case 270: return "W"
    case 315: return "NW"
    default: return ""
    }
}

var body: some View {
    VStack {
        Text(directionText)
            .font(.caption)
            .rotationEffect(Angle(degrees: -degree + currentHeading))
    }
    .offset(y: -125)
    .rotationEffect(Angle(degrees: degree))
}
}


*/




/*
// works tapi mau di pecah jadi file kecil, dan ada info dari Apple program crash saat mau export

import SwiftUI
import AVFoundation
import CoreLocation

class LocationManager: NSObject, ObservableObject {
    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    
    @Published var heading: Double = 0
    @Published var altitude: Double = 0
    @Published var accuracy: CLLocationAccuracy = 0
    @Published var coordinates: CLLocationCoordinate2D?
    
    // New published properties for location details
    @Published var placeName: String = "Unknown Location"
    @Published var country: String = ""
    @Published var administrativeArea: String = ""
    @Published var subAdministrativeArea: String = ""
    @Published var locality: String = ""
    @Published var subLocality: String = ""
    @Published var thoroughfare: String = ""
    
    override init() {
        super.init()
        setupLocationManager()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
    }
    
    private func performReverseGeocoding(for location: CLLocation) {
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let placemark = placemarks?.first, error == nil else {
                self?.resetLocationDetails()
                return
            }
            
            DispatchQueue.main.async {
                // Update location details
                self?.country = placemark.country ?? ""
                self?.administrativeArea = placemark.administrativeArea ?? ""
                self?.subAdministrativeArea = placemark.subAdministrativeArea ?? ""
                self?.locality = placemark.locality ?? ""
                self?.subLocality = placemark.subLocality ?? ""
                self?.thoroughfare = placemark.thoroughfare ?? ""
                
                // Create a formatted place name
                var nameParts = [String]()
                if let subLocality = placemark.subLocality, !subLocality.isEmpty {
                    nameParts.append(subLocality)
                }
                if let locality = placemark.locality, !locality.isEmpty {
                    nameParts.append(locality)
                }
                if let subAdministrative = placemark.subAdministrativeArea, !subAdministrative.isEmpty {
                    nameParts.append(subAdministrative)
                }
                if let administrative = placemark.administrativeArea, !administrative.isEmpty {
                    nameParts.append(administrative)
                }
                if let country = placemark.country, !country.isEmpty {
                    nameParts.append(country)
                }
                
                self?.placeName = nameParts.joined(separator: ", ")
            }
        }
    }
    
    private func resetLocationDetails() {
        DispatchQueue.main.async {
            self.placeName = "Unknown Location"
            self.country = ""
            self.administrativeArea = ""
            self.subAdministrativeArea = ""
            self.locality = ""
            self.subLocality = ""
            self.thoroughfare = ""
        }
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        DispatchQueue.main.async {
            self.heading = newHeading.magneticHeading
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        DispatchQueue.main.async {
            self.altitude = location.altitude
            self.accuracy = location.horizontalAccuracy
            self.coordinates = location.coordinate
            
            // Perform reverse geocoding
            self.performReverseGeocoding(for: location)
        }
    }
}




// Delegate for handling video capture events
class VideoCaptureDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("Video recording error: \(error.localizedDescription)")
        }
        print("Video recorded successfully: \(outputFileURL.absoluteString)")
    }
}

struct ContentView: View {
    // State variables
    @State private var isRecording = false
    @State private var captureSession: AVCaptureSession?
    @State private var videoOutput: AVCaptureMovieFileOutput?
    @State private var videoURL: URL?
    private let videoCaptureDelegate = VideoCaptureDelegate()
  
    @State private var showCompass = false
//    @State private var showCompass: Bool = false
    @State private var showExplain: Bool = false
    @State private var selectedQuality = VideoQuality.low // Default quality selection
    
    var body: some View {
        ZStack {
            // Background Gradient
            LinearGradient(colors: [Color(#colorLiteral(red: 0.5738074183, green: 0.5655357838, blue: 0, alpha: 1)),.clear], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack {
                HStack{
                    
                    Button(action: {
                        showCompass = true
                    }) {
                        Image(systemName: "location.north.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white)
                            .padding()
                    }
                 
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
                Spacer()
                
                
                
                
                // Start/Stop Recording Button
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
                .background(isRecording ? Color(#colorLiteral(red: 1, green: 0.8323456645, blue: 0.4732058644, alpha: 1)) : Color.white )
                .cornerRadius(25)
                .foregroundColor(isRecording ? Color.black : Color.black)
                .padding(.bottom, 18)
                
                // Export Button
                Button(action: {
                    self.exportVideo()
                }) {
                    Text("Export")
                }
                .font(.title2)
                .padding()
                .frame(width: 233)
                .background( Color(#colorLiteral(red: 0.5738074183, green: 0.5655357838, blue: 0, alpha: 1)) )
                .cornerRadius(25)
                .foregroundColor(.white)
                Spacer()
            }
            .onAppear {
                self.setupCamera()
            }
            .sheet(isPresented: $showCompass) {
                showCompassView(onConfirm: {
                    showCompass = false
                })
            }
            
//            .sheet(isPresented: $showCompass, onDismiss: {
//                UserDefaults.standard.set(selectedQuality.rawValue, forKey: "SelectedVideoQuality")
//                updateCaptureSessionPreset()
//            }) {
//                showCompassView()
//            }
           
            .sheet(isPresented: $showExplain, onDismiss: {
                UserDefaults.standard.set(selectedQuality.rawValue, forKey: "SelectedVideoQuality")
                updateCaptureSessionPreset()
            }) {
                ShowExplainView(captureSession: $captureSession, selectedQuality: $selectedQuality, isPresented: $showExplain)
            }
        }
    }
    
    // Setup the camera session
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
    
    // Start video recording
    func startRecording() {
        guard let videoOutput = self.videoOutput else {
            print("Video output is nil.")
            return
        }

        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let fileURL = paths[0].appendingPathComponent("video\(Date().timeIntervalSince1970).mp4")
        
        do {
            try videoOutput.startRecording(to: fileURL, recordingDelegate: videoCaptureDelegate)
            self.isRecording = true
            self.videoURL = fileURL
        } catch {
            print("Error starting recording: \(error.localizedDescription)")
        }
    }

    // Stop video recording
    func stopRecording() {
        guard let videoOutput = self.videoOutput else {
            print("Video output is nil.")
            return
        }

        if videoOutput.isRecording {
            videoOutput.stopRecording()
            self.isRecording = false
        }
    }

    // Export video

    func exportVideo() {
        guard let videoURL = self.videoURL else {
            print("Video URL is nil.")
            return
        }

        let activityViewController = UIActivityViewController(activityItems: [videoURL], applicationActivities: nil)
        UIApplication.shared.windows.first?.rootViewController?.present(activityViewController, animated: true, completion: nil)
    }

    
    // Update capture session preset based on selected video quality
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






struct AppCardView: View {
    var imageName: String
    var appName: String
    var appDescription: String
    var appURL: String
    
    var body: some View {
        HStack {
            Image(imageName)
                .resizable()
                .scaledToFill()
                .frame(width: 60, height: 60)
                .cornerRadius(7)
            
            VStack(alignment: .leading, content: {
                Text(appName)
                    .font(.title3)
                Text(appDescription)
                    .font(.caption)
            })
            .frame(alignment: .leading)
            
            Spacer()
            Button(action: {
                if let url = URL(string: appURL) {
                    UIApplication.shared.open(url)
                }
            }) {
                Text("Try")
                    .font(.headline)
                    .padding()
                    .foregroundColor(.white)
                    .background(Color.blue)
                    .cornerRadius(10)
            }
        }
    }
}


// MARK: - Compass View

struct showCompassView: View {
    var onConfirm: () -> Void
    @StateObject private var locationManager = LocationManager()
    @State private var isCopied = false
    
    var body: some View {
        ZStack {
            // Background Gradient
            LinearGradient(colors: [Color(#colorLiteral(red: 0.5738074183, green: 0.5655357838, blue: 0, alpha: 1)),.clear], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack {
                Spacer()
                ZStack {
                    // Compass background circle
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                        .frame(width: 250, height: 250)
                    
                    // Compass Rose
                    Image(systemName: "arrow.up")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 30, height: 30)
                        .foregroundColor(.red)
                        .rotationEffect(Angle(degrees: -locationManager.heading))
                    
                    // Compass markings
                    ForEach(0..<360, id: \.self) { degree in
                        if degree % 45 == 0 {
                            CompassMarkView(degree: Double(degree), currentHeading: locationManager.heading)
                        }
                    }
                }
                .rotationEffect(Angle(degrees: locationManager.heading))
                
                Spacer()
                
                Text("Current Heading: \(Int(locationManager.heading))°")
                    .padding()
                
                VStack(alignment: .leading, spacing: 10) {
                    // Display place name
                    HStack {
                        Image(systemName: "mappin.circle")
                        Text(locationManager.placeName)
                            .fontWeight(.bold)
                    }
                    
                    HStack {
                        Image(systemName: "arrow.up.and.down.circle")
                        Text("Altitude: \(String(format: "%.1f", locationManager.altitude)) m")
                    }
                    
                    // Coordinates Display
                    if let coords = locationManager.coordinates {
                        HStack {
                            Image(systemName: "map")
                            Text("Coordinates:")
                            Text(coordinatesString(coords))
                                .fontWeight(.bold)
                        }
                    }
                    
                    HStack {
                        Image(systemName: "location.circle")
                        Text("Accuracy: \(String(format: "%.1f", locationManager.accuracy)) m")
                            .foregroundColor(accuracyColor)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                
                Spacer()
          
                // Close button
                Button("Close") {
                    onConfirm()
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(#colorLiteral(red: 0.5738074183, green: 0.5655357838, blue: 0, alpha: 1)))
                .foregroundColor(.white)
                .font(.title3.bold())
                .cornerRadius(10)
                .padding()
              
                // Large Copy Button
//                Button(action: {
//                    copyLocationInformation()
//                }) {
//                    HStack {
//                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
//                        Text(isCopied ? "Copied!" : "Copy Location Details")
//                    }
//                    .frame(maxWidth: .infinity)
//                    .padding()
//                    .background(isCopied ? Color.blue : Color(#colorLiteral(red: 0.5738074183, green: 0.5655357838, blue: 0, alpha: 1)))
//                    .foregroundColor(.black)
//                    .cornerRadius(10)
//                    .font(.headline)
//                }
//                .padding()
            }
        }
    }
    
    // Format coordinates for easy sharing
    func coordinatesString(_ coordinate: CLLocationCoordinate2D) -> String {
        return String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude)
    }
    
    // Copy location information
    func copyLocationInformation() {
        guard let coords = locationManager.coordinates else { return }
        
        let locationInfo = """
        Location: \(locationManager.placeName)
        Heading: \(Int(locationManager.heading))°
        Altitude: \(String(format: "%.1f", locationManager.altitude)) m
        Coordinates: \(coordinatesString(coords))
        Accuracy: \(String(format: "%.1f", locationManager.accuracy)) m
        
        Detailed Location:
        Country: \(locationManager.country)
        Administrative Area: \(locationManager.administrativeArea)
        Sub-Administrative Area: \(locationManager.subAdministrativeArea)
        Locality: \(locationManager.locality)
        Sub-Locality: \(locationManager.subLocality)
        Thoroughfare: \(locationManager.thoroughfare)
        """
        
        UIPasteboard.general.string = locationInfo
        isCopied = true
        
        // Reset copied state after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isCopied = false
        }
    }
    
    var accuracyColor: Color {
        switch locationManager.accuracy {
        case ..<0:
            return .red  // Invalid location
        case 0..<10:
            return .green  // Very accurate
        case 10..<50:
            return .yellow  // Moderate accuracy
        default:
            return .red  // Poor accuracy
        }
    }
}

// MARK: - Explanation View

struct ShowExplainView: View {
    @Binding var captureSession: AVCaptureSession?
    @Binding var selectedQuality: VideoQuality // Add this line
    @Binding var isPresented: Bool
    @StateObject private var locationManager = LocationManager()

    var body: some View {
        ScrollView {
            ZStack {
                LinearGradient(colors: [Color(#colorLiteral(red: 0.5738074183, green: 0.5655357838, blue: 0, alpha: 1)),.clear], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                VStack {
                    
                    // Video Quality Picker
                    HStack {
                        Text("Video Quality")
                            .font(.title.bold())
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                    Picker("Video Quality", selection: $selectedQuality) {
                        Text("Low").tag(VideoQuality.low)
                        Text("Medium").tag(VideoQuality.medium)
                        Text("High").tag(VideoQuality.high)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding()
                    .foregroundColor(.white)
                    
                    
                    Spacer()
            
                  
              
                    
                    
                    
                    // App Functionality Explanation
                    HStack{
                        Text("App Functionality")
                            .font(.title.bold())
                        
                        //make it bigger
                            .font(.title3)
                        
                        
                        
                        
                        
                        
                        Spacer()
                    }
                    Text("""
                    • Press start to begin recording video.
                    • Press stop to stop recording.
                    • Press export to export the file.
                    • The app overwrites previous data when the start button is pressed again.
                    • The app cannot run in the background; auto-lock should be set to 'Never' to avoid turning off due to inactivity.
                    • Video quality should not be changed during recording to avoid stopping the record session.
                    """)
                    .font(.title3)
                    .multilineTextAlignment(.leading)
                    .padding()
                    
                    HStack {
                        Text("BODYCam is developed by Three Dollar.")
                            .font(.title3.bold())
                        Spacer()
                        
                    }
                    Spacer()
                    
                    HStack{
                        Text("App for you")
                            .font(.title.bold())
                        
                        
                        Spacer()
                    }
                    
                    // App Cards
                    VStack {
                        
                        
                        
                        //                    Divider().background(Color.gray)
                        //                    AppCardView(imageName: "sos", appName: "SOS Light", appDescription: "SOS Light is designed to maximize the chances of getting help in emergency situations.", appURL: "https://apps.apple.com/app/s0s-light/id6504213303")
                        //                    Divider().background(Color.gray)
                        //
                        //
                        
                        //                    AppCardView(imageName: "temptation", appName: "TemptationTrack", appDescription: "One button to track milestones, monitor progress, stay motivated.", appURL: "https://apps.apple.com/id/app/temptationtrack/id6471236988")
                        //                    Divider().background(Color.gray)
                        //                    // Add more AppCardViews here if needed
                        //                    // App Data
                        //
                        
                        AppCardView(imageName: "timetell", appName: "TimeTell", appDescription: "Announce the time every 30 seconds, no more guessing and checking your watch, for time-sensitive tasks.", appURL: "https://apps.apple.com/id/app/loopspeak/id6473384030")
                        Divider().background(Color.gray)
                        
                        //                    AppCardView(imageName: "BST", appName: "Blink Screen Time", appDescription: "Using screens can reduce your blink rate to just 6 blinks per minute, leading to dry eyes and eye strain. Our app helps you maintain a healthy blink rate to prevent these issues and keep your eyes comfortable.", appURL: "https://apps.apple.com/id/app/blink-screen-time/id6587551095")
                        //                    Divider().background(Color.gray)
                        
                        //                    AppCardView(imageName: "SingLoop", appName: "Sing LOOP", appDescription: "Record your voice effortlessly, and play it back in a loop.", appURL: "https://apps.apple.com/id/app/sing-l00p/id6480459464")
                        //                    Divider().background(Color.gray)
                        //
                        //                    AppCardView(imageName: "loopspeak", appName: "LOOPSpeak", appDescription: "Type or paste your text, play in loop, and enjoy hands-free narration.", appURL: "https://apps.apple.com/id/app/loopspeak/id6473384030")
                        //                    Divider().background(Color.gray)
                        
                        AppCardView(imageName: "insomnia", appName: "Insomnia Sheep", appDescription: "The Ultimate Sleep App you need.", appURL: "https://apps.apple.com/id/app/insomnia-sheep/id6479727431")
                        Divider().background(Color.gray)
                        
                        //                    AppCardView(imageName: "dryeye", appName: "Dry Eye Read", appDescription: "The go-to solution for a comfortable reading experience, by adjusting font size and color to suit your reading experience.", appURL: "https://apps.apple.com/id/app/dry-eye-read/id6474282023")
                        //                    Divider().background(Color.gray)
                        
                        AppCardView(imageName: "iprogram", appName: "iProgramMe", appDescription: "Custom affirmations, schedule notifications, stay inspired daily.", appURL: "https://apps.apple.com/id/app/iprogramme/id6470770935")
                        Divider().background(Color.gray)
                        
                        //                    AppCardView(imageName: "worry", appName: "Worry Bin", appDescription: "A place for worry.", appURL: "https://apps.apple.com/id/app/worry-bin/id6498626727")
                        //                    Divider().background(Color.gray)
                        
                    }
                    Spacer()
                    
                    
                    
                    Button("Close") {
                        // Perform confirmation action
                        updateCaptureSessionPreset()
                        isPresented = false
                    }
                    .font(.title)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(#colorLiteral(red: 0.5738074183, green: 0.5655357838, blue: 0, alpha: 1)))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .padding(.vertical, 10)
                }
                .padding()
                .cornerRadius(15.0)
                .padding()
            }
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






// Compass marking view for cardinal and ordinal directions
struct CompassMarkView: View {
let degree: Double
let currentHeading: Double

var directionText: String {
    switch degree {
    case 0: return "N"
    case 45: return "NE"
    case 90: return "E"
    case 135: return "SE"
    case 180: return "S"
    case 225: return "SW"
    case 270: return "W"
    case 315: return "NW"
    default: return ""
    }
}

var body: some View {
    VStack {
        Text(directionText)
            .font(.caption)
            .rotationEffect(Angle(degrees: -degree + currentHeading))
    }
    .offset(y: -125)
    .rotationEffect(Angle(degrees: degree))
}
}

*/

/*
//udah bagus tapi mau ada tambahan

import SwiftUI
import AVFoundation
import CoreLocation

class LocationManager: NSObject, ObservableObject {
    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    
    @Published var heading: Double = 0
    @Published var altitude: Double = 0
    @Published var accuracy: CLLocationAccuracy = 0
    @Published var coordinates: CLLocationCoordinate2D?
    
    // New published properties for location details
    @Published var placeName: String = "Unknown Location"
    @Published var country: String = ""
    @Published var administrativeArea: String = ""
    @Published var subAdministrativeArea: String = ""
    @Published var locality: String = ""
    @Published var subLocality: String = ""
    @Published var thoroughfare: String = ""
    
    override init() {
        super.init()
        setupLocationManager()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.requestWhenInUseAuthorization()
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
    }
    
    private func performReverseGeocoding(for location: CLLocation) {
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let placemark = placemarks?.first, error == nil else {
                self?.resetLocationDetails()
                return
            }
            
            DispatchQueue.main.async {
                // Update location details
                self?.country = placemark.country ?? ""
                self?.administrativeArea = placemark.administrativeArea ?? ""
                self?.subAdministrativeArea = placemark.subAdministrativeArea ?? ""
                self?.locality = placemark.locality ?? ""
                self?.subLocality = placemark.subLocality ?? ""
                self?.thoroughfare = placemark.thoroughfare ?? ""
                
                // Create a formatted place name
                var nameParts = [String]()
                if let subLocality = placemark.subLocality, !subLocality.isEmpty {
                    nameParts.append(subLocality)
                }
                if let locality = placemark.locality, !locality.isEmpty {
                    nameParts.append(locality)
                }
                if let subAdministrative = placemark.subAdministrativeArea, !subAdministrative.isEmpty {
                    nameParts.append(subAdministrative)
                }
                if let administrative = placemark.administrativeArea, !administrative.isEmpty {
                    nameParts.append(administrative)
                }
                if let country = placemark.country, !country.isEmpty {
                    nameParts.append(country)
                }
                
                self?.placeName = nameParts.joined(separator: ", ")
            }
        }
    }
    
    private func resetLocationDetails() {
        DispatchQueue.main.async {
            self.placeName = "Unknown Location"
            self.country = ""
            self.administrativeArea = ""
            self.subAdministrativeArea = ""
            self.locality = ""
            self.subLocality = ""
            self.thoroughfare = ""
        }
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        DispatchQueue.main.async {
            self.heading = newHeading.magneticHeading
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        DispatchQueue.main.async {
            self.altitude = location.altitude
            self.accuracy = location.horizontalAccuracy
            self.coordinates = location.coordinate
            
            // Perform reverse geocoding
            self.performReverseGeocoding(for: location)
        }
    }
}




// Delegate for handling video capture events
class VideoCaptureDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("Video recording error: \(error.localizedDescription)")
        }
        print("Video recorded successfully: \(outputFileURL.absoluteString)")
    }
}

struct ContentView: View {
    // State variables
    @State private var isRecording = false
    @State private var captureSession: AVCaptureSession?
    @State private var videoOutput: AVCaptureMovieFileOutput?
    @State private var videoURL: URL?
    private let videoCaptureDelegate = VideoCaptureDelegate()
  
    @State private var showCompass: Bool = false
    @State private var showExplain: Bool = false
    @State private var selectedQuality = VideoQuality.low // Default quality selection
    
    var body: some View {
        ZStack {
            // Background Gradient
            LinearGradient(colors: [Color(#colorLiteral(red: 0.5738074183, green: 0.5655357838, blue: 0, alpha: 1)),.clear], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack {
                HStack{
                    
                    Button(action: {
                        showCompass = true
                    }) {
                        Image(systemName: "location.north.circle.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white)
                            .padding()
                    }
                 
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
                Spacer()
                
                
                
                
                // Start/Stop Recording Button
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
                .background(isRecording ? Color(#colorLiteral(red: 1, green: 0.8323456645, blue: 0.4732058644, alpha: 1)) : Color.white )
                .cornerRadius(25)
                .foregroundColor(isRecording ? Color.black : Color.black)
                .padding(.bottom, 18)
                
                // Export Button
                Button(action: {
                    self.exportVideo()
                }) {
                    Text("Export")
                }
                .font(.title2)
                .padding()
                .frame(width: 233)
                .background( Color(#colorLiteral(red: 0.5738074183, green: 0.5655357838, blue: 0, alpha: 1)) )
                .cornerRadius(25)
                .foregroundColor(.white)
                Spacer()
            }
            .onAppear {
                self.setupCamera()
            }
            
            .sheet(isPresented: $showCompass, onDismiss: {
                UserDefaults.standard.set(selectedQuality.rawValue, forKey: "SelectedVideoQuality")
                updateCaptureSessionPreset()
            }) {
                showCompassView()
            }
           
            .sheet(isPresented: $showExplain, onDismiss: {
                UserDefaults.standard.set(selectedQuality.rawValue, forKey: "SelectedVideoQuality")
                updateCaptureSessionPreset()
            }) {
                ShowExplainView(captureSession: $captureSession, selectedQuality: $selectedQuality, isPresented: $showExplain)
            }
        }
    }
    
    // Setup the camera session
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
    
    // Start video recording
    func startRecording() {
        guard let videoOutput = self.videoOutput else {
            print("Video output is nil.")
            return
        }

        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let fileURL = paths[0].appendingPathComponent("video\(Date().timeIntervalSince1970).mp4")
        
        do {
            try videoOutput.startRecording(to: fileURL, recordingDelegate: videoCaptureDelegate)
            self.isRecording = true
            self.videoURL = fileURL
        } catch {
            print("Error starting recording: \(error.localizedDescription)")
        }
    }

    // Stop video recording
    func stopRecording() {
        guard let videoOutput = self.videoOutput else {
            print("Video output is nil.")
            return
        }

        if videoOutput.isRecording {
            videoOutput.stopRecording()
            self.isRecording = false
        }
    }

    // Export video

    func exportVideo() {
        guard let videoURL = self.videoURL else {
            print("Video URL is nil.")
            return
        }

        let activityViewController = UIActivityViewController(activityItems: [videoURL], applicationActivities: nil)
        UIApplication.shared.windows.first?.rootViewController?.present(activityViewController, animated: true, completion: nil)
    }

    
    // Update capture session preset based on selected video quality
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






struct AppCardView: View {
    var imageName: String
    var appName: String
    var appDescription: String
    var appURL: String
    
    var body: some View {
        HStack {
            Image(imageName)
                .resizable()
                .scaledToFill()
                .frame(width: 60, height: 60)
                .cornerRadius(7)
            
            VStack(alignment: .leading, content: {
                Text(appName)
                    .font(.title3)
                Text(appDescription)
                    .font(.caption)
            })
            .frame(alignment: .leading)
            
            Spacer()
            Button(action: {
                if let url = URL(string: appURL) {
                    UIApplication.shared.open(url)
                }
            }) {
                Text("Try")
                    .font(.headline)
                    .padding()
                    .foregroundColor(.white)
                    .background(Color.blue)
                    .cornerRadius(10)
            }
        }
    }
}


// MARK: - Compass View

struct showCompassView: View {
    @StateObject private var locationManager = LocationManager()
    @State private var isCopied = false
    
    var body: some View {
        ZStack {
            // Background Gradient
            LinearGradient(colors: [Color(#colorLiteral(red: 0.5738074183, green: 0.5655357838, blue: 0, alpha: 1)),.clear], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack {
                Spacer()
                ZStack {
                    // Compass background circle
                    Circle()
                        .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                        .frame(width: 250, height: 250)
                    
                    // Compass Rose
                    Image(systemName: "arrow.up")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 30, height: 30)
                        .foregroundColor(.red)
                        .rotationEffect(Angle(degrees: -locationManager.heading))
                    
                    // Compass markings
                    ForEach(0..<360, id: \.self) { degree in
                        if degree % 45 == 0 {
                            CompassMarkView(degree: Double(degree), currentHeading: locationManager.heading)
                        }
                    }
                }
                .rotationEffect(Angle(degrees: locationManager.heading))
                
                Spacer()
                
                Text("Current Heading: \(Int(locationManager.heading))°")
                    .padding()
                
                VStack(alignment: .leading, spacing: 10) {
                    // Display place name
                    HStack {
                        Image(systemName: "mappin.circle")
                        Text(locationManager.placeName)
                            .fontWeight(.bold)
                    }
                    
                    HStack {
                        Image(systemName: "arrow.up.and.down.circle")
                        Text("Altitude: \(String(format: "%.1f", locationManager.altitude)) m")
                    }
                    
                    // Coordinates Display
                    if let coords = locationManager.coordinates {
                        HStack {
                            Image(systemName: "map")
                            Text("Coordinates:")
                            Text(coordinatesString(coords))
                                .fontWeight(.bold)
                        }
                    }
                    
                    HStack {
                        Image(systemName: "location.circle")
                        Text("Accuracy: \(String(format: "%.1f", locationManager.accuracy)) m")
                            .foregroundColor(accuracyColor)
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                
                Spacer()
                // Large Copy Button
                Button(action: {
                    copyLocationInformation()
                }) {
                    HStack {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        Text(isCopied ? "Copied!" : "Copy Location Details")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isCopied ? Color.blue : Color(#colorLiteral(red: 0.5738074183, green: 0.5655357838, blue: 0, alpha: 1)))
                    .foregroundColor(.black)
                    .cornerRadius(10)
                    .font(.headline)
                }
                .padding()
            }
        }
    }
    
    // Format coordinates for easy sharing
    func coordinatesString(_ coordinate: CLLocationCoordinate2D) -> String {
        return String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude)
    }
    
    // Copy location information
    func copyLocationInformation() {
        guard let coords = locationManager.coordinates else { return }
        
        let locationInfo = """
        Location: \(locationManager.placeName)
        Heading: \(Int(locationManager.heading))°
        Altitude: \(String(format: "%.1f", locationManager.altitude)) m
        Coordinates: \(coordinatesString(coords))
        Accuracy: \(String(format: "%.1f", locationManager.accuracy)) m
        
        Detailed Location:
        Country: \(locationManager.country)
        Administrative Area: \(locationManager.administrativeArea)
        Sub-Administrative Area: \(locationManager.subAdministrativeArea)
        Locality: \(locationManager.locality)
        Sub-Locality: \(locationManager.subLocality)
        Thoroughfare: \(locationManager.thoroughfare)
        """
        
        UIPasteboard.general.string = locationInfo
        isCopied = true
        
        // Reset copied state after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isCopied = false
        }
    }
    
    var accuracyColor: Color {
        switch locationManager.accuracy {
        case ..<0:
            return .red  // Invalid location
        case 0..<10:
            return .green  // Very accurate
        case 10..<50:
            return .yellow  // Moderate accuracy
        default:
            return .red  // Poor accuracy
        }
    }
}

// MARK: - Explanation View

struct ShowExplainView: View {
    @Binding var captureSession: AVCaptureSession?
    @Binding var selectedQuality: VideoQuality // Add this line
    @Binding var isPresented: Bool
    @StateObject private var locationManager = LocationManager()

    var body: some View {
        ScrollView {
            ZStack {
                LinearGradient(colors: [Color(#colorLiteral(red: 0.5738074183, green: 0.5655357838, blue: 0, alpha: 1)),.clear], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                VStack {
                    
                    // Video Quality Picker
                    HStack {
                        Text("Video Quality")
                            .font(.title.bold())
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                    Picker("Video Quality", selection: $selectedQuality) {
                        Text("Low").tag(VideoQuality.low)
                        Text("Medium").tag(VideoQuality.medium)
                        Text("High").tag(VideoQuality.high)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding()
                    .foregroundColor(.white)
                    
                    
                    Spacer()
            
                  
              
                    
                    
                    
                    // App Functionality Explanation
                    HStack{
                        Text("App Functionality")
                            .font(.title.bold())
                        
                        //make it bigger
                            .font(.title3)
                        
                        
                        
                        
                        
                        
                        Spacer()
                    }
                    Text("""
                    • Press start to begin recording video.
                    • Press stop to stop recording.
                    • Press export to export the file.
                    • The app overwrites previous data when the start button is pressed again.
                    • The app cannot run in the background; auto-lock should be set to 'Never' to avoid turning off due to inactivity.
                    • Video quality should not be changed during recording to avoid stopping the record session.
                    """)
                    .font(.title3)
                    .multilineTextAlignment(.leading)
                    .padding()
                    
                    HStack {
                        Text("BODYCam is developed by Three Dollar.")
                            .font(.title3.bold())
                        Spacer()
                        
                    }
                    Spacer()
                    
                    HStack{
                        Text("App for you")
                            .font(.title.bold())
                        
                        
                        Spacer()
                    }
                    
                    // App Cards
                    VStack {
                        
                        
                        
                        //                    Divider().background(Color.gray)
                        //                    AppCardView(imageName: "sos", appName: "SOS Light", appDescription: "SOS Light is designed to maximize the chances of getting help in emergency situations.", appURL: "https://apps.apple.com/app/s0s-light/id6504213303")
                        //                    Divider().background(Color.gray)
                        //
                        //
                        
                        //                    AppCardView(imageName: "temptation", appName: "TemptationTrack", appDescription: "One button to track milestones, monitor progress, stay motivated.", appURL: "https://apps.apple.com/id/app/temptationtrack/id6471236988")
                        //                    Divider().background(Color.gray)
                        //                    // Add more AppCardViews here if needed
                        //                    // App Data
                        //
                        
                        AppCardView(imageName: "timetell", appName: "TimeTell", appDescription: "Announce the time every 30 seconds, no more guessing and checking your watch, for time-sensitive tasks.", appURL: "https://apps.apple.com/id/app/loopspeak/id6473384030")
                        Divider().background(Color.gray)
                        
                        //                    AppCardView(imageName: "BST", appName: "Blink Screen Time", appDescription: "Using screens can reduce your blink rate to just 6 blinks per minute, leading to dry eyes and eye strain. Our app helps you maintain a healthy blink rate to prevent these issues and keep your eyes comfortable.", appURL: "https://apps.apple.com/id/app/blink-screen-time/id6587551095")
                        //                    Divider().background(Color.gray)
                        
                        //                    AppCardView(imageName: "SingLoop", appName: "Sing LOOP", appDescription: "Record your voice effortlessly, and play it back in a loop.", appURL: "https://apps.apple.com/id/app/sing-l00p/id6480459464")
                        //                    Divider().background(Color.gray)
                        //
                        //                    AppCardView(imageName: "loopspeak", appName: "LOOPSpeak", appDescription: "Type or paste your text, play in loop, and enjoy hands-free narration.", appURL: "https://apps.apple.com/id/app/loopspeak/id6473384030")
                        //                    Divider().background(Color.gray)
                        
                        AppCardView(imageName: "insomnia", appName: "Insomnia Sheep", appDescription: "The Ultimate Sleep App you need.", appURL: "https://apps.apple.com/id/app/insomnia-sheep/id6479727431")
                        Divider().background(Color.gray)
                        
                        //                    AppCardView(imageName: "dryeye", appName: "Dry Eye Read", appDescription: "The go-to solution for a comfortable reading experience, by adjusting font size and color to suit your reading experience.", appURL: "https://apps.apple.com/id/app/dry-eye-read/id6474282023")
                        //                    Divider().background(Color.gray)
                        
                        AppCardView(imageName: "iprogram", appName: "iProgramMe", appDescription: "Custom affirmations, schedule notifications, stay inspired daily.", appURL: "https://apps.apple.com/id/app/iprogramme/id6470770935")
                        Divider().background(Color.gray)
                        
                        //                    AppCardView(imageName: "worry", appName: "Worry Bin", appDescription: "A place for worry.", appURL: "https://apps.apple.com/id/app/worry-bin/id6498626727")
                        //                    Divider().background(Color.gray)
                        
                    }
                    Spacer()
                    
                    
                    
                    Button("Close") {
                        // Perform confirmation action
                        updateCaptureSessionPreset()
                        isPresented = false
                    }
                    .font(.title)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(#colorLiteral(red: 0.5738074183, green: 0.5655357838, blue: 0, alpha: 1)))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .padding(.vertical, 10)
                }
                .padding()
                .cornerRadius(15.0)
                .padding()
            }
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






// Compass marking view for cardinal and ordinal directions
struct CompassMarkView: View {
let degree: Double
let currentHeading: Double

var directionText: String {
    switch degree {
    case 0: return "N"
    case 45: return "NE"
    case 90: return "E"
    case 135: return "SE"
    case 180: return "S"
    case 225: return "SW"
    case 270: return "W"
    case 315: return "NW"
    default: return ""
    }
}

var body: some View {
    VStack {
        Text(directionText)
            .font(.caption)
            .rotationEffect(Angle(degrees: -degree + currentHeading))
    }
    .offset(y: -125)
    .rotationEffect(Angle(degrees: degree))
}
}



*/

/*

//sudah launch cuma mau ada revisi/ update

import SwiftUI
import AVFoundation

// Delegate for handling video capture events
class VideoCaptureDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("Video recording error: \(error.localizedDescription)")
        }
        print("Video recorded successfully: \(outputFileURL.absoluteString)")
    }
}

struct ContentView: View {
    // State variables
    @State private var isRecording = false
    @State private var captureSession: AVCaptureSession?
    @State private var videoOutput: AVCaptureMovieFileOutput?
    @State private var videoURL: URL?
    private let videoCaptureDelegate = VideoCaptureDelegate()
  
    @State private var showExplain: Bool = false
    @State private var selectedQuality = VideoQuality.low // Default quality selection
    
    var body: some View {
        ZStack {
            // Background Gradient
            LinearGradient(colors: [Color(#colorLiteral(red: 0.5738074183, green: 0.5655357838, blue: 0, alpha: 1)),.clear], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack {
                HStack{
                 
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
                Spacer()
                
                
                
                
                // Start/Stop Recording Button
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
                .background(isRecording ? Color(#colorLiteral(red: 1, green: 0.8323456645, blue: 0.4732058644, alpha: 1)) : Color.white )
                .cornerRadius(25)
                .foregroundColor(isRecording ? Color.black : Color.black)
                .padding(.bottom, 18)
                
                // Export Button
                Button(action: {
                    self.exportVideo()
                }) {
                    Text("Export")
                }
                .font(.title2)
                .padding()
                .frame(width: 233)
                .background( Color(#colorLiteral(red: 0.5738074183, green: 0.5655357838, blue: 0, alpha: 1)) )
                .cornerRadius(25)
                .foregroundColor(.white)
                Spacer()
            }
            .onAppear {
                self.setupCamera()
            }
           
            .sheet(isPresented: $showExplain, onDismiss: {
                UserDefaults.standard.set(selectedQuality.rawValue, forKey: "SelectedVideoQuality")
                updateCaptureSessionPreset()
            }) {
                ShowExplainView(captureSession: $captureSession, selectedQuality: $selectedQuality, isPresented: $showExplain)
            }
        }
    }
    
    // Setup the camera session
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
    
    // Start video recording
    func startRecording() {
        guard let videoOutput = self.videoOutput else {
            print("Video output is nil.")
            return
        }

        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let fileURL = paths[0].appendingPathComponent("video\(Date().timeIntervalSince1970).mp4")
        
        do {
            try videoOutput.startRecording(to: fileURL, recordingDelegate: videoCaptureDelegate)
            self.isRecording = true
            self.videoURL = fileURL
        } catch {
            print("Error starting recording: \(error.localizedDescription)")
        }
    }

    // Stop video recording
    func stopRecording() {
        guard let videoOutput = self.videoOutput else {
            print("Video output is nil.")
            return
        }

        if videoOutput.isRecording {
            videoOutput.stopRecording()
            self.isRecording = false
        }
    }

    // Export video

    func exportVideo() {
        guard let videoURL = self.videoURL else {
            print("Video URL is nil.")
            return
        }

        let activityViewController = UIActivityViewController(activityItems: [videoURL], applicationActivities: nil)
        UIApplication.shared.windows.first?.rootViewController?.present(activityViewController, animated: true, completion: nil)
    }

    
    // Update capture session preset based on selected video quality
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






struct AppCardView: View {
    var imageName: String
    var appName: String
    var appDescription: String
    var appURL: String
    
    var body: some View {
        HStack {
            Image(imageName)
                .resizable()
                .scaledToFill()
                .frame(width: 60, height: 60)
                .cornerRadius(7)
            
            VStack(alignment: .leading, content: {
                Text(appName)
                    .font(.title3)
                Text(appDescription)
                    .font(.caption)
            })
            .frame(alignment: .leading)
            
            Spacer()
            Button(action: {
                if let url = URL(string: appURL) {
                    UIApplication.shared.open(url)
                }
            }) {
                Text("Try")
                    .font(.headline)
                    .padding()
                    .foregroundColor(.white)
                    .background(Color.blue)
                    .cornerRadius(10)
            }
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
               
                // Video Quality Picker
                HStack {
                    Text("Video Quality")
                        .font(.title.bold())
                        .multilineTextAlignment(.leading)
                    Spacer()
                }
                Picker("Video Quality", selection: $selectedQuality) {
                    Text("Low").tag(VideoQuality.low)
                    Text("Medium").tag(VideoQuality.medium)
                    Text("High").tag(VideoQuality.high)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                .foregroundColor(.white)
                
                
                
                // App Functionality Explanation
                HStack{
                    Text("App Functionality")
                        .font(.title.bold())
                  
                    //make it bigger
                        .font(.title3)
               
                    
                    
              
                    
                    
                    Spacer()
                }
                Text("""
                • Press start to begin recording video.
                • Press stop to stop recording.
                • Press export to export the file.
                • The app overwrites previous data when the start button is pressed again.
                • The app cannot run in the background; auto-lock should be set to 'Never' to avoid turning off due to inactivity.
                • Video quality should not be changed during recording to avoid stopping the record session.
                """)
                .font(.title3)
                .multilineTextAlignment(.leading)
                .padding()
                
                HStack {
                    Text("BODYCam is developed by Three Dollar.")
                        .font(.title3.bold())
                    Spacer()
                    
                }
                Spacer()
                
                HStack{
                    Text("App for you")
                        .font(.title.bold())
                    
                    
                    Spacer()
                }
             
                // App Cards
                VStack {
                         
             
                    
//                    Divider().background(Color.gray)
//                    AppCardView(imageName: "sos", appName: "SOS Light", appDescription: "SOS Light is designed to maximize the chances of getting help in emergency situations.", appURL: "https://apps.apple.com/app/s0s-light/id6504213303")
//                    Divider().background(Color.gray)
//             
//                
                    
//                    AppCardView(imageName: "temptation", appName: "TemptationTrack", appDescription: "One button to track milestones, monitor progress, stay motivated.", appURL: "https://apps.apple.com/id/app/temptationtrack/id6471236988")
//                    Divider().background(Color.gray)
//                    // Add more AppCardViews here if needed
//                    // App Data
//                 
                    
                    AppCardView(imageName: "timetell", appName: "TimeTell", appDescription: "Announce the time every 30 seconds, no more guessing and checking your watch, for time-sensitive tasks.", appURL: "https://apps.apple.com/id/app/loopspeak/id6473384030")
                    Divider().background(Color.gray)
                    
//                    AppCardView(imageName: "BST", appName: "Blink Screen Time", appDescription: "Using screens can reduce your blink rate to just 6 blinks per minute, leading to dry eyes and eye strain. Our app helps you maintain a healthy blink rate to prevent these issues and keep your eyes comfortable.", appURL: "https://apps.apple.com/id/app/blink-screen-time/id6587551095")
//                    Divider().background(Color.gray)
                    
//                    AppCardView(imageName: "SingLoop", appName: "Sing LOOP", appDescription: "Record your voice effortlessly, and play it back in a loop.", appURL: "https://apps.apple.com/id/app/sing-l00p/id6480459464")
//                    Divider().background(Color.gray)
//                    
//                    AppCardView(imageName: "loopspeak", appName: "LOOPSpeak", appDescription: "Type or paste your text, play in loop, and enjoy hands-free narration.", appURL: "https://apps.apple.com/id/app/loopspeak/id6473384030")
//                    Divider().background(Color.gray)
                    
                    AppCardView(imageName: "insomnia", appName: "Insomnia Sheep", appDescription: "The Ultimate Sleep App you need.", appURL: "https://apps.apple.com/id/app/insomnia-sheep/id6479727431")
                    Divider().background(Color.gray)
                    
//                    AppCardView(imageName: "dryeye", appName: "Dry Eye Read", appDescription: "The go-to solution for a comfortable reading experience, by adjusting font size and color to suit your reading experience.", appURL: "https://apps.apple.com/id/app/dry-eye-read/id6474282023")
//                    Divider().background(Color.gray)
                    
                    AppCardView(imageName: "iprogram", appName: "iProgramMe", appDescription: "Custom affirmations, schedule notifications, stay inspired daily.", appURL: "https://apps.apple.com/id/app/iprogramme/id6470770935")
                    Divider().background(Color.gray)
                    
//                    AppCardView(imageName: "worry", appName: "Worry Bin", appDescription: "A place for worry.", appURL: "https://apps.apple.com/id/app/worry-bin/id6498626727")
//                    Divider().background(Color.gray)
                
                }
                Spacer()
               


                Button("Close") {
                    // Perform confirmation action
                    updateCaptureSessionPreset()
                    isPresented = false
                }
                .font(.title)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
                .padding(.vertical, 10)
            }
            .padding()
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
        MainAppView()
    }
}


*/

/*
//dapat review dari App Store button export tidak responsive dan crash saat record, jadi di perbaiki


import SwiftUI
import AVFoundation

// Delegate for handling video capture events
class VideoCaptureDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("Video recording error: \(error.localizedDescription)")
        }
        print("Video recorded successfully: \(outputFileURL.absoluteString)")
    }
}

struct ContentView: View {
    // State variables
    @State private var isRecording = false
    @State private var captureSession: AVCaptureSession?
    @State private var videoOutput: AVCaptureMovieFileOutput?
    @State private var videoURL: URL?
    private let videoCaptureDelegate = VideoCaptureDelegate()
  
    @State private var showExplain: Bool = false
    @State private var selectedQuality = VideoQuality.low // Default quality selection
    
    var body: some View {
        ZStack {
            // Background Gradient
            LinearGradient(colors: [Color(#colorLiteral(red: 0.5738074183, green: 0.5655357838, blue: 0, alpha: 1)),.clear], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack {
                HStack{
                 
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
                Spacer()
                // Start/Stop Recording Button
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
                .background(isRecording ? Color(#colorLiteral(red: 1, green: 0.8323456645, blue: 0.4732058644, alpha: 1)) : Color.white )
                .cornerRadius(25)
                .foregroundColor(isRecording ? Color.black : Color.black)
                .padding(.bottom, 18)
                
                // Export Button
                Button(action: {
                    self.exportVideo()
                }) {
                    Text("Export")
                }
                .font(.title2)
                .padding()
                .frame(width: 233)
                .background( Color(#colorLiteral(red: 0.5738074183, green: 0.5655357838, blue: 0, alpha: 1)) )
                .cornerRadius(25)
                .foregroundColor(.white)
                Spacer()
            }
            .onAppear {
                self.setupCamera()
            }
           
            .sheet(isPresented: $showExplain, onDismiss: {
                UserDefaults.standard.set(selectedQuality.rawValue, forKey: "SelectedVideoQuality")
                updateCaptureSessionPreset()
            }) {
                ShowExplainView(captureSession: $captureSession, selectedQuality: $selectedQuality, isPresented: $showExplain)
            }
        }
    }
    
    // Setup the camera session
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
    
    // Start video recording
    func startRecording() {
        guard let videoOutput = self.videoOutput else { return }
        
        let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        let fileURL = paths[0].appendingPathComponent("video\(Date().timeIntervalSince1970).mp4")
        videoOutput.startRecording(to: fileURL, recordingDelegate: videoCaptureDelegate)
        self.isRecording = true
        self.videoURL = fileURL
    }
    
    // Stop video recording
    func stopRecording() {
        guard let videoOutput = self.videoOutput else { return }
        videoOutput.stopRecording()
        self.isRecording = false
    }
    
    // Export video
    func exportVideo() {
        guard let videoURL = self.videoURL else { return }
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            let activityViewController = UIActivityViewController(activityItems: [videoURL], applicationActivities: nil)
            window.rootViewController?.present(activityViewController, animated: true, completion: nil)
        }
    }
    
    // Update capture session preset based on selected video quality
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






struct AppCardView: View {
    var imageName: String
    var appName: String
    var appDescription: String
    var appURL: String
    
    var body: some View {
        HStack {
            Image(imageName)
                .resizable()
                .scaledToFill()
                .frame(width: 60, height: 60)
                .cornerRadius(7)
            
            VStack(alignment: .leading, content: {
                Text(appName)
                    .font(.title3)
                Text(appDescription)
                    .font(.caption)
            })
            .frame(alignment: .leading)
            
            Spacer()
            Button(action: {
                if let url = URL(string: appURL) {
                    UIApplication.shared.open(url)
                }
            }) {
                Text("Try")
                    .font(.headline)
                    .padding()
                    .foregroundColor(.white)
                    .background(Color.blue)
                    .cornerRadius(10)
            }
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
               
                // Video Quality Picker
                HStack {
                    Text("Video Quality")
                        .font(.title.bold())
                        .multilineTextAlignment(.leading)
                    Spacer()
                }
                Picker("Video Quality", selection: $selectedQuality) {
                    Text("Low").tag(VideoQuality.low)
                    Text("Medium").tag(VideoQuality.medium)
                    Text("High").tag(VideoQuality.high)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                .foregroundColor(.white)
                
                // App Functionality Explanation
                HStack{
                    Text("App Functionality")
                        .font(.title.bold())
                    Spacer()
                }
                Text("""
                • Press start to begin recording video.
                • Press stop to stop recording.
                • Press export to export the file.
                • The app overwrites previous data when the start button is pressed again.
                • The app cannot run in the background; auto-lock should be set to 'Never' to avoid turning off due to inactivity.
                • Video quality should not be changed during recording to avoid stopping the record session.
                """)
                .font(.title3)
                .multilineTextAlignment(.leading)
                .padding()
                
                HStack {
                    Text("BODYCam is developed by Three Dollar.")
                        .font(.title3.bold())
                    Spacer()
                }
                Spacer()
                
                HStack{
                    Text("Ads")
                        .font(.title.bold())
                    
                    
                    Spacer()
                }
                ZStack {
                    Image("threedollar")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .cornerRadius(25)
                        .clipped()
                        .onTapGesture {
                            if let url = URL(string: "https://b33.biz/three-dollar/") {
                                UIApplication.shared.open(url)
                            }
                        }
                }
                // App Cards
                VStack {
                    Divider().background(Color.gray)
                    AppCardView(imageName: "temptation", appName: "TemptationTrack", appDescription: "One button to track milestones, monitor progress, stay motivated.", appURL: "https://apps.apple.com/id/app/temptationtrack/id6471236988")
                    Divider().background(Color.gray)
                    // Add more AppCardViews here if needed
                    // App Data
                 
                    
                    AppCardView(imageName: "timetell", appName: "TimeTell", appDescription: "Announce the time every 30 seconds, no more guessing and checking your watch, for time-sensitive tasks.", appURL: "https://apps.apple.com/id/app/loopspeak/id6473384030")
                    Divider().background(Color.gray)
                    
                    AppCardView(imageName: "SingLoop", appName: "Sing LOOP", appDescription: "Record your voice effortlessly, and play it back in a loop.", appURL: "https://apps.apple.com/id/app/sing-l00p/id6480459464")
                    Divider().background(Color.gray)
                    
                    AppCardView(imageName: "loopspeak", appName: "LOOPSpeak", appDescription: "Type or paste your text, play in loop, and enjoy hands-free narration.", appURL: "https://apps.apple.com/id/app/loopspeak/id6473384030")
                    Divider().background(Color.gray)
                    
                    AppCardView(imageName: "insomnia", appName: "Insomnia Sheep", appDescription: "Design to ease your mind and help you relax leading up to sleep.", appURL: "https://apps.apple.com/id/app/insomnia-sheep/id6479727431")
                    Divider().background(Color.gray)
                    
                    AppCardView(imageName: "dryeye", appName: "Dry Eye Read", appDescription: "The go-to solution for a comfortable reading experience, by adjusting font size and color to suit your reading experience.", appURL: "https://apps.apple.com/id/app/dry-eye-read/id6474282023")
                    Divider().background(Color.gray)
                    
                    AppCardView(imageName: "iprogram", appName: "iProgramMe", appDescription: "Custom affirmations, schedule notifications, stay inspired daily.", appURL: "https://apps.apple.com/id/app/iprogramme/id6470770935")
                    Divider().background(Color.gray)
                    
                    AppCardView(imageName: "worry", appName: "Worry Bin", appDescription: "A place for worry.", appURL: "https://apps.apple.com/id/app/worry-bin/id6498626727")
                    Divider().background(Color.gray)
                
                }
                Spacer()
               


                Button("Close") {
                    // Perform confirmation action
                    updateCaptureSessionPreset()
                    isPresented = false
                }
                .font(.title)
                .padding()
                .cornerRadius(25.0)
                .padding()
            }
            .padding()
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

*/

//code work well ready to submit app store
/*
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
                .background( Color(#colorLiteral(red: 0.5741485357, green: 0.5741624236, blue: 0.574154973, alpha: 1)) )
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
                HStack {
                    Text("Ads")
                        .font(.largeTitle.bold())
                        
                    Spacer()
                }
                ZStack {
                    Image("threedollar")
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .cornerRadius(25)
                        .clipped()
                        .onTapGesture {
                            if let url = URL(string: "https://b33.biz/three-dollar/") {
                                UIApplication.shared.open(url)
                            }
                        }
//                    VStack(alignment: .leading, content: {
//                        Spacer()
//                        Text("Three Dollar")
//                            .font(.title3.bold())
//                        Text("At Three Dollar, apps are priced at $3. We blend simplicity with effectiveness to address specific problems.")
//                            .font(.caption)
//                            
//                    })
//                    .foregroundColor(.black)
//                    .frame(maxWidth: .infinity, alignment: .leading)
//                    .padding()
                    
                    
                
                }
               
                VStack{
                    HStack {
                        Text("Three Dollar Apps")
                            .font(.title.bold())
                            .frame(height: 70)
                            
                        Spacer()
                    }
                    Divider().background(Color.gray)
                    HStack {
                        
                        Image("SingLoop")
                            .resizable()
                            .scaledToFill()
                        .frame(width: 60, height: 60)
                        .cornerRadius(7)
                        
                        
                        VStack(alignment: .leading, content: {
                            Text("SingLoop")
                                .font(.title3)
                            Text("Record your voice effortlessly, and play it back in a loop.")
                                .font(.caption)
                        })
                        .frame(alignment: .leading)
                        
                        Spacer()
                        Button(action: {
                            if let url = URL(string: "https://apps.apple.com/id/app/sing-l00p/id6480459464") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            Text("Get")
                                .font(.headline)
                                .padding()
                                .foregroundColor(.white)
                                .background(Color.blue)
                                .cornerRadius(10)
                        }
                        
                    }
                    Divider().background(Color.gray)
                    
                    HStack {
                        
                        Image("timetell")
                            .resizable()
                            .scaledToFill()
                        .frame(width: 60, height: 60)
                        .cornerRadius(7)
                        
                        
                        VStack(alignment: .leading, content: {
                            Text("TimeTell")
                                .font(.title3)
                            Text("Announce the time every 30 seconds, no more guessing and checking your watch, for time-sensitive tasks.")
                                .font(.caption)
                        })
                        .frame(alignment: .leading)
                        
                        Spacer()
                        Button(action: {
                            if let url = URL(string: "https://apps.apple.com/id/app/loopspeak/id6473384030") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            Text("Get")
                                .font(.headline)
                                .padding()
                                .foregroundColor(.white)
                                .background(Color.blue)
                                .cornerRadius(10)
                        }
                        
                    }
                    Divider().background(Color.gray)
                    HStack {
                        
                        Image("loopspeak")
                            .resizable()
                            .scaledToFill()
                        .frame(width: 60, height: 60)
                        .cornerRadius(7)
                        
                        
                        VStack(alignment: .leading, content: {
                            Text("LOOPSpeak")
                                .font(.title3)
                            Text("Type or paste your text, play in loop, and enjoy hands-free narration.")
                                .font(.caption)
                        })
                        .frame(alignment: .leading)
                        
                        Spacer()
                        Button(action: {
                            if let url = URL(string: "https://apps.apple.com/id/app/loopspeak/id6473384030") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            Text("Get")
                                .font(.headline)
                                .padding()
                                .foregroundColor(.white)
                                .background(Color.blue)
                                .cornerRadius(10)
                        }
                        
                    }
                    Divider().background(Color.gray)
                    HStack {
                        
                        Image("insomnia")
                            .resizable()
                            .scaledToFill()
                        .frame(width: 60, height: 60)
                        .cornerRadius(7)
                        
                        
                        VStack(alignment: .leading, content: {
                            Text("Insomnia Sheep")
                                .font(.title3)
                            Text("Design to ease your mind and help you relax leading up to sleep.")
                                .font(.caption)
                        })
                        .frame(alignment: .leading)
                        
                        Spacer()
                        Button(action: {
                            if let url = URL(string: "https://apps.apple.com/id/app/insomnia-sheep/id6479727431") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            Text("Get")
                                .font(.headline)
                                .padding()
                                .foregroundColor(.white)
                                .background(Color.blue)
                                .cornerRadius(10)
                        }
                        
                    }
                    
                    Divider().background(Color.gray)
                    HStack {
                        
                        Image("dryeye")
                            .resizable()
                            .scaledToFill()
                        .frame(width: 60, height: 60)
                        .cornerRadius(7)
                        
                        
                        VStack(alignment: .leading, content: {
                            Text("Dry Eye Read")
                                .font(.title3)
                            Text("The go-to solution for a comfortable reading experience, by adjusting font size and color to suit your reading experience.")
                                .font(.caption)
                        })
                        .frame(alignment: .leading)
                        
                        Spacer()
                        Button(action: {
                            if let url = URL(string: "https://apps.apple.com/id/app/dry-eye-read/id6474282023") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            Text("Get")
                                .font(.headline)
                                .padding()
                                .foregroundColor(.white)
                                .background(Color.blue)
                                .cornerRadius(10)
                        }
                        
                    }

                    Divider().background(Color.gray)
                    HStack {
                        
                        Image("iprogram")
                            .resizable()
                            .scaledToFill()
                        .frame(width: 60, height: 60)
                        .cornerRadius(7)
                        
                        
                        VStack(alignment: .leading, content: {
                            Text("iProgramMe")
                                .font(.title3)
                            Text("Custom affirmations, schedule notifications, stay inspired daily.")
                                .font(.caption)
                        })
                        .frame(alignment: .leading)
                        
                        Spacer()
                        Button(action: {
                            if let url = URL(string: "https://apps.apple.com/id/app/iprogramme/id6470770935") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            Text("Get")
                                .font(.headline)
                                .padding()
                                .foregroundColor(.white)
                                .background(Color.blue)
                                .cornerRadius(10)
                        }
                        
                    }
                    Divider().background(Color.gray)
                    HStack {
                        
                        Image("temptation")
                            .resizable()
                            .scaledToFill()
                        .frame(width: 60, height: 60)
                        .cornerRadius(7)
                        
                        
                        VStack(alignment: .leading, content: {
                            Text("TemptationTrack")
                                .font(.title3)
                            Text("One button to track milestones, monitor progress, stay motivated.")
                                .font(.caption)
                        })
                        .frame(alignment: .leading)
                        
                        Spacer()
                        Button(action: {
                            if let url = URL(string: "https://apps.apple.com/id/app/temptationtrack/id6471236988") {
                                UIApplication.shared.open(url)
                            }
                        }) {
                            Text("Get")
                                .font(.headline)
                                .padding()
                                .foregroundColor(.white)
                                .background(Color.blue)
                                .cornerRadius(10)
                        }
                        
                    }
                    Divider().background(Color.gray)


                    //
                }
                   
             
                
    

               Spacer()

               Button("Close") {
                   // Perform confirmation action
                   onConfirm()
               }
               .font(.title)
               .padding()
              
               .cornerRadius(25.0)
               .padding()
           }
           .padding()
//           .background(Color(#colorLiteral(red: 0.5738074183, green: 0.5655357838, blue: 0, alpha: 1)))
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
                HStack {
                    Text("Video Quality")
                        .font(.title.bold())
                        .multilineTextAlignment(.leading)
    //                    .multilineTextAlignment(.center)
//                    .padding()
                    Spacer()
                }
//                    .foregroundColor(.white)

                Picker("Video Quality", selection: $selectedQuality) {
                    Text("Low").tag(VideoQuality.low)
                    Text("Medium").tag(VideoQuality.medium)
                    Text("High").tag(VideoQuality.high)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                .foregroundColor(.white)
                
                HStack{
                    Text("App Functionality")
                        .font(.title.bold())
                        
                    Spacer()
                }
                
                Text("""
• Press start to begin recording video.
• Press stop to stop recording.
• Press export to export the file.
• The app overwrites previous data when the start button is pressed again.
• The app cannot run in the background; auto-lock should be set to 'Never' to avoid turning off due to inactivity.
• Video quality should not be changed during recording to avoid stopping the record session.
""")
                    .font(.title3)
                    .multilineTextAlignment(.leading)
                    .padding()
                   

                Spacer()

                Button("Close") {
                    // Perform confirmation action
                    updateCaptureSessionPreset()
                    isPresented = false
                }
                .font(.title)
                .padding()
//                .foregroundColor(.black)
//                .background(Color.white)
                .cornerRadius(25.0)
                .padding()
            }
            .padding()
//            .background(Color(#colorLiteral(red: 0.5738074183, green: 0.5655357838, blue: 0, alpha: 1)))
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

*/
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
