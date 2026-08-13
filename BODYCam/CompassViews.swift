import SwiftUI
import CoreLocation

// MARK: - Compass Detail Sheet

struct CompassView: View {
    var onConfirm: () -> Void
    @StateObject private var locationManager = LocationManager()

    var body: some View {
        ZStack {
            backgroundLayer

            VStack {
                Spacer()
                CompassRoseView(heading: locationManager.heading)
                Spacer()

                Text("Current Heading: \(Int(locationManager.heading))°")
                    .padding()
                    .foregroundColor(.lightGray)

                locationInfoPanel
                Spacer()
                closeButton
            }
            .padding()
        }
    }

    // MARK: Sub-views

    private var backgroundLayer: some View {
        ZStack {
            Image("pattern1").resizable().ignoresSafeArea()
            LinearGradient(
                colors: [Color(#colorLiteral(red: 0.26, green: 0.26, blue: 0.26, alpha: 1)),
                         Color(#colorLiteral(red: 0.476, green: 0.476, blue: 0.476, alpha: 1))],
                startPoint: .top, endPoint: .bottom
            ).opacity(0.7).ignoresSafeArea()
        }
    }

    private var locationInfoPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "mappin.circle")
                Text(locationManager.placeName).fontWeight(.bold).foregroundColor(.lightGray)
            }
            HStack {
                Image(systemName: "arrow.up.and.down.circle")
                Text("Altitude: \(String(format: "%.1f", locationManager.altitude)) m").foregroundColor(.lightGray)
            }
            if let coords = locationManager.coordinates {
                HStack {
                    Image(systemName: "map")
                    Text("Coordinates:").foregroundColor(.lightGray)
                    Text(coordinatesString(coords)).fontWeight(.bold).foregroundColor(.lightGray)
                }
            }
            HStack {
                Image(systemName: "location.circle")
                Text("Accuracy: \(String(format: "%.1f", locationManager.accuracy)) m").foregroundColor(.lightGray)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(10)
    }

    private var closeButton: some View {
        Button("Close") { onConfirm() }
            .font(.title)
            .frame(maxWidth: .infinity)
            .padding()
            .background(darkButtonGradient)
            .foregroundColor(.white)
            .cornerRadius(10)
            .shadow(color: .black.opacity(0.4), radius: 8, x: 4, y: 4)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.8), lineWidth: 1))
            .padding(.vertical, 10)
    }

    // MARK: Helpers

    func coordinatesString(_ coordinate: CLLocationCoordinate2D) -> String {
        String(format: "%.6f, %.6f", coordinate.latitude, coordinate.longitude)
    }
}

// MARK: - Compass Rose

struct CompassRoseView: View {
    let heading: Double
    var size: CGFloat = 250
    var arrowSize: CGFloat = 99
    var strokeWidth: CGFloat = 33
    var strokeColor: Color = Color(#colorLiteral(red: 0.72, green: 0.89, blue: 0.59, alpha: 1)).opacity(0.85)
    var arrowColor: Color = Color(#colorLiteral(red: 1, green: 0.83, blue: 0.47, alpha: 1))

    var body: some View {
        ZStack {
            compassBackground
            Image(systemName: "location.north.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: arrowSize, height: arrowSize)
                .foregroundColor(arrowColor)
                .rotationEffect(.degrees(-heading))
            ForEach(0..<360, id: \.self) { degree in
                if degree % 45 == 0 {
                    CompassMarkView(degree: Double(degree), currentHeading: heading)
                }
            }
        }
        .rotationEffect(.degrees(heading))
    }

    private var compassBackground: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(
                    gradient: Gradient(colors: [.black, Color(white: 0.5)]),
                    center: .topLeading, startRadius: 10, endRadius: 400
                ))
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.5), radius: 15, x: 10, y: 10)
                .overlay(Circle().stroke(Color.black.opacity(0.5), lineWidth: 2))
                .overlay(
                    Circle().stroke(
                        RadialGradient(
                            gradient: Gradient(colors: [.white.opacity(0.5), .clear]),
                            center: .center, startRadius: 1, endRadius: size / 2
                        ),
                        lineWidth: strokeWidth
                    )
                )
            Circle().stroke(strokeColor, lineWidth: strokeWidth).frame(width: size, height: size)
        }
    }
}

// MARK: - Compass Mark

struct CompassMarkView: View {
    let degree: Double
    let currentHeading: Double

    var directionText: String {
        switch degree {
        case 0:   return "N"
        case 45:  return "NE"
        case 90:  return "E"
        case 135: return "SE"
        case 180: return "S"
        case 225: return "SW"
        case 270: return "W"
        case 315: return "NW"
        default:  return ""
        }
    }

    var body: some View {
        Text(directionText)
            .font(.caption)
            .rotationEffect(.degrees(-degree + currentHeading))
            .offset(y: -125)
            .rotationEffect(.degrees(degree))
    }
}

// MARK: - Shared Gradient

var darkButtonGradient: LinearGradient {
    LinearGradient(
        gradient: Gradient(colors: [
            Color(#colorLiteral(red: 0.255, green: 0.275, blue: 0.302, alpha: 1)),
            Color(#colorLiteral(red: 0.392, green: 0.412, blue: 0.435, alpha: 1))
        ]),
        startPoint: .top, endPoint: .bottom
    )
}

// MARK: - Color Extension

extension Color {
    static let lightGray = Color(#colorLiteral(red: 0.804, green: 0.804, blue: 0.804, alpha: 1))
}
