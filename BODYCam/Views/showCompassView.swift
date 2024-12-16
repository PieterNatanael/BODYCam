/// MARK: - Compass View
//
//struct showCompassView: View {
//    var onConfirm: () -> Void
//    @StateObject private var locationManager = LocationManager()
//    @State private var isCopied = false
//    
//    var body: some View {
//        ZStack {
//            // Background Gradient
//            LinearGradient(colors: [Color(#colorLiteral(red: 0.5738074183, green: 0.5655357838, blue: 0, alpha: 1)),.clear], startPoint: .top, endPoint: .bottom)
//                .ignoresSafeArea()
//            VStack {
//                Spacer()
//                ZStack {
//                    // Compass background circle
//                    Circle()
//                        .stroke(Color.gray.opacity(0.3), lineWidth: 2)
//                        .frame(width: 250, height: 250)
//                    
//                    // Compass Rose
//                    Image(systemName: "arrow.up")
//                        .resizable()
//                        .aspectRatio(contentMode: .fit)
//                        .frame(width: 30, height: 30)
//                        .foregroundColor(.red)
//                        .rotationEffect(Angle(degrees: -locationManager.heading))
//                    
//                    // Compass markings
//                    ForEach(0..<360, id: \.self) { degree in
//                        if degree % 45 == 0 {
//                            CompassMarkView(degree: Double(degree), currentHeading: locationManager.heading)
//                        }
//                    }
//                }
//                .rotationEffect(Angle(degrees: locationManager.heading))
//                
//                Spacer()
//                
//                Text("Current Heading: \(Int(locationManager.heading))°")
//                    .padding()
//                
//                VStack(alignment: .leading, spacing: 10) {
//                    // Display place name
//                    HStack {
//                        Image(systemName: "mappin.circle")
//                        Text(locationManager.placeName)
//                            .fontWeight(.bold)
//                    }
//                    
//                    HStack {
//                        Image(systemName: "arrow.up.and.down.circle")
//                        Text("Altitude: \(String(format: "%.1f", locationManager.altitude)) m")
//                    }
//                    
//                    // Coordinates Display
//                    if let coords = locationManager.coordinates {
//                        HStack {
//                            Image(systemName: "map")
//                            Text("Coordinates:")
//                            Text(coordinatesString(coords))
//                                .fontWeight(.bold)
//                        }
//                    }
//                    
//                    HStack {
//                        Image(systemName: "location.circle")
//                        Text("Accuracy: \(String(format: "%.1f", locationManager.accuracy)) m")
//                            .foregroundColor(accuracyColor)
//                    }
//                }
//                .padding()
//                .background(Color.gray.opacity(0.1))
//                .cornerRadius(10)
//                
//                Spacer()
//          
//                // Close button
//                Button("Close") {
//                    onConfirm()
//                }
//                .frame(maxWidth: .infinity)
//                .padding()
//                .background(Color(#colorLiteral(red: 0.5738074183, green: 0.5655357838, blue: 0, alpha: 1)))
//                .foregroundColor(.white)
//                .font(.title3.bold())
//                .cornerRadius(10)
//                .padding()
//              
//                // Large Copy Button
////                Button(action: {
////                    copyLocationInformation()
////                }) {
////                    HStack {
////                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
////                        Text(isCopied ? "Copied!" : "Copy Location Details")
////                    }
////                    .frame(maxWidth: .infinity)
////                    .padding()
////                    .background(isCopied ? Color.blue : Color(#colorLiteral(red: 0.5738074183, green: 0.5655357838, blue: 0, alpha: 1)))
////                    .foregroundColor(.black)
////                    .cornerRadius(10)
////                    .font(.headline)
////                }
////                .padding()
//            }
//        }
//    }
//    
//    // Format coordinates for easy sharing
//    func coordinatesString(_ coordinate: CLLocationCoordinate2D) -> String {
//        return String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude)
//    }
//    
//    // Copy location information
//    func copyLocationInformation() {
//        guard let coords = locationManager.coordinates else { return }
//        
//        let locationInfo = """
//        Location: \(locationManager.placeName)
//        Heading: \(Int(locationManager.heading))°
//        Altitude: \(String(format: "%.1f", locationManager.altitude)) m
//        Coordinates: \(coordinatesString(coords))
//        Accuracy: \(String(format: "%.1f", locationManager.accuracy)) m
//        
//        Detailed Location:
//        Country: \(locationManager.country)
//        Administrative Area: \(locationManager.administrativeArea)
//        Sub-Administrative Area: \(locationManager.subAdministrativeArea)
//        Locality: \(locationManager.locality)
//        Sub-Locality: \(locationManager.subLocality)
//        Thoroughfare: \(locationManager.thoroughfare)
//        """
//        
//        UIPasteboard.general.string = locationInfo
//        isCopied = true
//        
//        // Reset copied state after 2 seconds
//        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
//            isCopied = false
//        }
//    }
//    
//    var accuracyColor: Color {
//        switch locationManager.accuracy {
//        case ..<0:
//            return .red  // Invalid location
//        case 0..<10:
//            return .green  // Very accurate
//        case 10..<50:
//            return .yellow  // Moderate accuracy
//        default:
//            return .red  // Poor accuracy
//        }
//    }
//}