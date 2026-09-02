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

/// Carries the bottom marker's position, in points below the visible
/// scroll viewport's own bottom edge, up to the view that decides whether
/// to show the scroll hint. Negative once the marker has scrolled up past
/// that edge and into view.
private struct ScrollMarkerOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = .infinity
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct OnboardingView: View {
    var onAccept: () -> Void

    // The accept button lives outside the ScrollView (see body) so it is
    // always on screen regardless of how long the copy above it is. This
    // hint only covers the separate problem of someone not realizing there
    // is more to read before it — true once, until the invisible marker at
    // the bottom of the scrollable copy comes into view.
    @State private var showsScrollHint = true
    @State private var chevronBounce = false

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                GeometryReader { viewportGeo in
                    ZStack(alignment: .bottom) {
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

                                Spacer().frame(height: 24)

                                // Invisible — its only job is to report, via
                                // GeometryReader, how far it still is below the
                                // bottom of the visible scroll viewport. A plain
                                // VStack isn't lazy, so onAppear/onDisappear here
                                // would fire the moment the view is built, not
                                // when it actually scrolls into sight — this is
                                // the real way to detect that in a ScrollView.
                                GeometryReader { markerGeo in
                                    Color.clear.preference(
                                        key: ScrollMarkerOffsetKey.self,
                                        value: markerGeo.frame(in: .named("onboardingScroll")).minY
                                            - viewportGeo.size.height)
                                }
                                .frame(height: 1)

                                Spacer().frame(height: 20)
                            }
                        }
                        .coordinateSpace(name: "onboardingScroll")

                        if showsScrollHint {
                            scrollHint
                                .transition(.opacity)
                        }
                    }
                }
                .onPreferenceChange(ScrollMarkerOffsetKey.self) { offset in
                    // Small negative margin so the hint clears just before the
                    // marker's exact pixel becomes visible, not right at it.
                    showsScrollHint = offset > -12
                }

                acceptButton
                    .padding(.top, 14)
                    .padding(.bottom, 10)
                    .overlay(
                        Rectangle().fill(Color(white: 0.25)).frame(height: 1),
                        alignment: .top
                    )
            }
            .animation(.easeInOut(duration: 0.25), value: showsScrollHint)
        }
    }

    // MARK: - Scroll hint

    private var scrollHint: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, .black.opacity(0.65)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 60)
            .allowsHitTesting(false)

            VStack(spacing: 2) {
                Text("SCROLL FOR MORE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(Color(white: 0.8))
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(Color(white: 0.8))
                    .offset(y: chevronBounce ? 3 : -3)
            }
            .padding(.bottom, 8)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    chevronBounce = true
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

            // Text(verbatim:) rather than a plain literal: a bare Text("LBC")
            // is a LocalizedStringKey, so Xcode extracts the product name into
            // the string catalog as if it were translatable prose. verbatim
            // keeps it out of the catalog entirely, which is what a brand name
            // should be.
            Text(verbatim: "LBC")
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
