//
//  OnboardingView.swift
//  BODYCam
//
//  The one time first run screen. Replaces the earlier DisclaimerView, which
//  showed only the data loss warnings — those are still here, below a plain
//  explanation of which permissions the app asks for and why.
//
//  The permissions half exists because iOS shows each system prompt cold, one
//  at a time, with only the short Info.plist string for context. Explaining
//  all four up front (and being explicit that two of them are optional) means
//  the prompts arrive already understood rather than as a surprise.
//
//  Scrollable rather than fixed: there is more copy here than the old screen
//  had, and it still has to fit an iPhone SE.
//

import SwiftUI

struct OnboardingView: View {
    var onAccept: () -> Void

    var body: some View {
        ZStack {
            background

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer().frame(height: 50)

                    header

                    Spacer().frame(height: 34)

                    permissionsSection

                    Spacer().frame(height: 22)

                    privacyNote

                    Spacer().frame(height: 30)

                    warningsSection

                    Spacer().frame(height: 34)

                    acceptButton

                    Spacer().frame(height: 40)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 14) {
            // The real app icon rather than an SF Symbol, so the first thing
            // someone sees matches the icon they just tapped on the home
            // screen. Sourced from its own imageset: an AppIcon asset cannot
            // be loaded by name, so the artwork is duplicated into
            // LBCLogo.imageset specifically to be displayable in the UI.
            Image("LBCLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 84, height: 84)
                .cornerRadius(18)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color(white: 0.35), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 4)

            // Product name, deliberately never localized.
            Text("LBC")
                .font(.system(size: 30, weight: .heavy, design: .monospaced))
                .foregroundColor(.lightGray)
                .tracking(6)

            Text("WELCOME")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(Color(white: 0.45))
                .tracking(4)

            Text("Here is what the app needs, and why.")
                .font(.system(size: 13))
                .foregroundColor(Color(white: 0.6))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 28)
                .padding(.top, 4)
        }
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            permissionRow(
                icon: "camera.fill",
                title: "CAMERA",
                detail: "To record video and take photos. The app cannot work without this.")

            permissionRow(
                icon: "mic.fill",
                title: "MICROPHONE",
                detail: "To record sound along with your videos.")

            permissionRow(
                icon: "photo.fill",
                title: "PHOTOS",
                detail: "Only used when you choose to save a photo or video to your library.")

            permissionRow(
                icon: "bell.fill",
                title: "NOTIFICATIONS",
                detail: "Only used if you set an alarm or reminder for something you saved.")
        }
        .padding(.horizontal, 28)
    }

    private func permissionRow(icon: String, title: LocalizedStringKey,
                               detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(Color(red: 1.0, green: 0.75, blue: 0.2))
                .frame(width: 22)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundColor(Color(white: 0.85))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundColor(Color(white: 0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var privacyNote: some View {
        Text("Everything you record stays on your device. We do not collect it, upload it, or share it with anyone.")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(Color(white: 0.7))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 28)
    }

    // MARK: - Data loss warnings
    //
    // Carried over verbatim from the screen this replaces. Shortening or
    // dropping any of it is a decision for the app's owner, not a side effect
    // of a redesign, so the wording is unchanged.

    private var warningsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("BEFORE YOU START")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(Color(white: 0.45))
                .tracking(3)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 2)

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
    }

    private func warningRow(icon: String, text: LocalizedStringKey) -> some View {
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

    // MARK: - Accept

    private var acceptButton: some View {
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
