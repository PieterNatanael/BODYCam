import SwiftUI

struct DisclaimerView: View {
    var onAccept: () -> Void

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                Spacer()

                // Icon + title
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 60))
                        .foregroundColor(Color(red: 1.0, green: 0.75, blue: 0.2))

                    Text("LB Camera")
                        .font(.system(size: 28, weight: .heavy, design: .monospaced))
                        .foregroundColor(.lightGray)
                        .tracking(4)

                    Text("IMPORTANT NOTICE")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(white: 0.45))
                        .tracking(4)
                }

                Spacer().frame(height: 40)

                // Warning bullets
                VStack(alignment: .leading, spacing: 16) {
                    warningRow(icon: "exclamationmark.triangle.fill",
                               text: "We do not guarantee recordings will be saved. Data loss can occur due to bugs, crashes, or device issues.")

                    warningRow(icon: "arrow.triangle.2.circlepath",
                               text: "App updates may cause unexpected behaviour that could affect recording reliability.")

                    warningRow(icon: "bolt.fill",
                               text: "Interrupted recordings (low battery, force-quit, calls) may result in corrupted or missing files.")

                    warningRow(icon: "externaldrive.fill",
                               text: "Always back up important footage to a safe location immediately after recording.")

                    warningRow(icon: "person.fill.xmark",
                               text: "This app is provided as-is. We are not liable for any data loss or corruption.")
                }
                .padding(.horizontal, 28)

                Spacer().frame(height: 40)

                // Accept button
                Button(action: onAccept) {
                    Text("I Understand")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(darkButtonGradient)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .shadow(color: .black.opacity(0.5), radius: 8, x: 4, y: 4)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(white: 0.4), lineWidth: 1))
                }
                .padding(.horizontal, 28)

                Spacer()
            }
        }
    }

    // MARK: - Sub-views

    private func warningRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(Color(red: 1.0, green: 0.75, blue: 0.2))
                .frame(width: 20)
                .padding(.top, 2)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(Color(white: 0.65))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var background: some View {
        ZStack {
            Image("pattern1").resizable().ignoresSafeArea()
            LinearGradient(
                colors: [.black, Color(#colorLiteral(red: 0.476, green: 0.476, blue: 0.476, alpha: 1))],
                startPoint: .top, endPoint: .bottom
            ).opacity(0.92).ignoresSafeArea()
        }
    }
}
