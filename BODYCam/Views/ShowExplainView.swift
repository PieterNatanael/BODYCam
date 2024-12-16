//// MARK: - Explanation View
//
//struct ShowExplainView: View {
//    @Binding var captureSession: AVCaptureSession?
//    @Binding var selectedQuality: VideoQuality // Add this line
//    @Binding var isPresented: Bool
//    @StateObject private var locationManager = LocationManager()
//
//    var body: some View {
//        ScrollView {
//            ZStack {
//                LinearGradient(colors: [Color(#colorLiteral(red: 0.5738074183, green: 0.5655357838, blue: 0, alpha: 1)),.clear], startPoint: .top, endPoint: .bottom)
//                    .ignoresSafeArea()
//                VStack {
//                    
//                    // Video Quality Picker
//                    HStack {
//                        Text("Video Quality")
//                            .font(.title.bold())
//                            .multilineTextAlignment(.leading)
//                        Spacer()
//                    }
//                    Picker("Video Quality", selection: $selectedQuality) {
//                        Text("Low").tag(VideoQuality.low)
//                        Text("Medium").tag(VideoQuality.medium)
//                        Text("High").tag(VideoQuality.high)
//                    }
//                    .pickerStyle(SegmentedPickerStyle())
//                    .padding()
//                    .foregroundColor(.white)
//                    
//                    
//                    Spacer()
//            
//                  
//              
//                    
//                    
//                    
//                    // App Functionality Explanation
//                    HStack{
//                        Text("App Functionality")
//                            .font(.title.bold())
//                        
//                        //make it bigger
//                            .font(.title3)
//                        
//                        
//                        
//                        
//                        
//                        
//                        Spacer()
//                    }
//                    Text("""
//                    • Press start to begin recording video.
//                    • Press stop to stop recording.
//                    • Press export to export the file.
//                    • The app overwrites previous data when the start button is pressed again.
//                    • The app cannot run in the background; auto-lock should be set to 'Never' to avoid turning off due to inactivity.
//                    • Video quality should not be changed during recording to avoid stopping the record session.
//                    """)
//                    .font(.title3)
//                    .multilineTextAlignment(.leading)
//                    .padding()
//                    
//                    HStack {
//                        Text("BODYCam is developed by Three Dollar.")
//                            .font(.title3.bold())
//                        Spacer()
//                        
//                    }
//                    Spacer()
//                    
//                    HStack{
//                        Text("App for you")
//                            .font(.title.bold())
//                        
//                        
//                        Spacer()
//                    }
//                    
//                    // App Cards
//                    VStack {
//                        
//                        
//                        
//                        //                    Divider().background(Color.gray)
//                        //                    AppCardView(imageName: "sos", appName: "SOS Light", appDescription: "SOS Light is designed to maximize the chances of getting help in emergency situations.", appURL: "https://apps.apple.com/app/s0s-light/id6504213303")
//                        //                    Divider().background(Color.gray)
//                        //
//                        //
//                        
//                        //                    AppCardView(imageName: "temptation", appName: "TemptationTrack", appDescription: "One button to track milestones, monitor progress, stay motivated.", appURL: "https://apps.apple.com/id/app/temptationtrack/id6471236988")
//                        //                    Divider().background(Color.gray)
//                        //                    // Add more AppCardViews here if needed
//                        //                    // App Data
//                        //
//                        
//                        AppCardView(imageName: "timetell", appName: "TimeTell", appDescription: "Announce the time every 30 seconds, no more guessing and checking your watch, for time-sensitive tasks.", appURL: "https://apps.apple.com/id/app/loopspeak/id6473384030")
//                        Divider().background(Color.gray)
//                        
//                        //                    AppCardView(imageName: "BST", appName: "Blink Screen Time", appDescription: "Using screens can reduce your blink rate to just 6 blinks per minute, leading to dry eyes and eye strain. Our app helps you maintain a healthy blink rate to prevent these issues and keep your eyes comfortable.", appURL: "https://apps.apple.com/id/app/blink-screen-time/id6587551095")
//                        //                    Divider().background(Color.gray)
//                        
//                        //                    AppCardView(imageName: "SingLoop", appName: "Sing LOOP", appDescription: "Record your voice effortlessly, and play it back in a loop.", appURL: "https://apps.apple.com/id/app/sing-l00p/id6480459464")
//                        //                    Divider().background(Color.gray)
//                        //
//                        //                    AppCardView(imageName: "loopspeak", appName: "LOOPSpeak", appDescription: "Type or paste your text, play in loop, and enjoy hands-free narration.", appURL: "https://apps.apple.com/id/app/loopspeak/id6473384030")
//                        //                    Divider().background(Color.gray)
//                        
//                        AppCardView(imageName: "insomnia", appName: "Insomnia Sheep", appDescription: "The Ultimate Sleep App you need.", appURL: "https://apps.apple.com/id/app/insomnia-sheep/id6479727431")
//                        Divider().background(Color.gray)
//                        
//                        //                    AppCardView(imageName: "dryeye", appName: "Dry Eye Read", appDescription: "The go-to solution for a comfortable reading experience, by adjusting font size and color to suit your reading experience.", appURL: "https://apps.apple.com/id/app/dry-eye-read/id6474282023")
//                        //                    Divider().background(Color.gray)
//                        
//                        AppCardView(imageName: "iprogram", appName: "iProgramMe", appDescription: "Custom affirmations, schedule notifications, stay inspired daily.", appURL: "https://apps.apple.com/id/app/iprogramme/id6470770935")
//                        Divider().background(Color.gray)
//                        
//                        //                    AppCardView(imageName: "worry", appName: "Worry Bin", appDescription: "A place for worry.", appURL: "https://apps.apple.com/id/app/worry-bin/id6498626727")
//                        //                    Divider().background(Color.gray)
//                        
//                    }
//                    Spacer()
//                    
//                    
//                    
//                    Button("Close") {
//                        // Perform confirmation action
//                        updateCaptureSessionPreset()
//                        isPresented = false
//                    }
//                    .font(.title)
//                    .frame(maxWidth: .infinity)
//                    .padding()
//                    .background(Color(#colorLiteral(red: 0.5738074183, green: 0.5655357838, blue: 0, alpha: 1)))
//                    .foregroundColor(.white)
//                    .cornerRadius(10)
//                    .padding(.vertical, 10)
//                }
//                .padding()
//                .cornerRadius(15.0)
//                .padding()
//            }
//        }
//        .onDisappear {
//            // Save the selected quality when the sheet is closed
//            UserDefaults.standard.set(selectedQuality.rawValue, forKey: "SelectedVideoQuality")
//        }
//        .onAppear {
//            // Load the selected quality when the sheet appears
//            if let storedQuality = UserDefaults.standard.value(forKey: "SelectedVideoQuality") as? Int,
//               let quality = VideoQuality(rawValue: storedQuality) {
//                selectedQuality = quality
//            }
//        }
//    }
//    
//   
//
//    func updateCaptureSessionPreset() {
//        switch selectedQuality {
//        case .low:
//            captureSession?.sessionPreset = .low
//        case .medium:
//            captureSession?.sessionPreset = .medium
//        case .high:
//            captureSession?.sessionPreset = .high
//        }
//    }
//}
//
//