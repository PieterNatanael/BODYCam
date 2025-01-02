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
                    .cornerRadius(11)
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



