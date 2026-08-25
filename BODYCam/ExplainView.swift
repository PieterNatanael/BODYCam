import SwiftUI
import AVFoundation

struct ExplainView: View {
    @Binding var captureSession: AVCaptureSession?
    @Binding var selectedQuality: VideoQuality
    @Binding var isPresented: Bool

    var body: some View {
        ZStack {
            backgroundLayer

            ScrollView {
                VStack(spacing: 16) {
                    qualityPicker
                    functionalitySection
                    appCardsSection
                    closeButton
                }
                .padding()
            }
            .onAppear {
                if let stored = UserDefaults.standard.object(forKey: "SelectedVideoQuality") as? Int,
                   let quality = VideoQuality(rawValue: stored) {
                    selectedQuality = quality
                }
            }
            .onDisappear {
                UserDefaults.standard.set(selectedQuality.rawValue, forKey: "SelectedVideoQuality")
            }
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

    private var qualityPicker: some View {
        VStack(alignment: .leading) {
            Text("Video Quality")
                .font(.title.bold())
                .foregroundColor(.lightGray)
            Picker("Video Quality", selection: $selectedQuality) {
                Text("Low").tag(VideoQuality.low)
                Text("Medium").tag(VideoQuality.medium)
                Text("High").tag(VideoQuality.high)
            }
            .pickerStyle(SegmentedPickerStyle())
        }
    }

    private var functionalitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("App Functionality")
                .font(.title.bold())
                .foregroundColor(.lightGray)
            Text("""
                • Press start to begin recording video.
                • Press stop to stop recording.
                • Press export to export the file.
                • The app overwrites previous data when the start button is pressed again.
                • The app cannot run in the background; auto-lock should be set to 'Never'.
                • Video quality should not be changed during recording.
                """)
                .font(.title3)
                .foregroundColor(.lightGray)
            Text("LBC — Low Battery Camera is developed by Three Dollar.")
                .font(.title3.bold())
                .foregroundColor(.lightGray)
        }
    }

    private var appCardsSection: some View {
        VStack(spacing: 0) {
            Text("App for you")
                .font(.title.bold())
                .foregroundColor(.lightGray)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)

            AppCardView(
                imageName: "timetell",
                appName: "TimeTell",
                appDescription: "Announce the time every 30 seconds, no more guessing and checking your watch.",
                appURL: "https://apps.apple.com/id/app/loopspeak/id6473384030"
            )
            Divider().background(Color.gray)

            AppCardView(
                imageName: "insomnia",
                appName: "Insomnia Sheep",
                appDescription: "The Ultimate Sleep App you need.",
                appURL: "https://apps.apple.com/id/app/insomnia-sheep/id6479727431"
            )
            Divider().background(Color.gray)

            AppCardView(
                imageName: "iprogram",
                appName: "iProgramMe",
                appDescription: "Custom affirmations, schedule notifications, stay inspired daily.",
                appURL: "https://apps.apple.com/id/app/iprogramme/id6470770935"
            )
        }
    }

    private var closeButton: some View {
        Button("Close") {
            applyQualityPreset()
            isPresented = false
        }
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

    private func applyQualityPreset() {
        captureSession?.sessionPreset = selectedQuality.preset
    }
}
