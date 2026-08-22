//
//  BODYCamApp.swift
//  BODYCam
//
//  Created by Pieter Yoshua Natanael on 13/04/24.
//

import SwiftUI

@main
struct BODYCamApp: App {
    // Receives notification taps — see AppDelegate.
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("AppLanguage") private var appLanguageRaw: String = AppLanguage.system.rawValue

    var body: some Scene {
        WindowGroup {
            // Applied at the true window root, not inside RootView, since a
            // .environment value set only on a child isn't guaranteed to
            // reach every future sheet — the window root always propagates
            // to everything it presents. @AppStorage here re-evaluates this
            // whenever the Settings picker changes it, so the switch is live,
            // no relaunch needed.
            RootView()
                .environment(\.locale, appLocale)
        }
    }

    private var appLocale: Locale {
        let language = AppLanguage(rawValue: appLanguageRaw) ?? .system
        guard let identifier = language.localeIdentifier else {
            // Live-tracks the device's own setting, including a change made
            // while the app is running — the same behavior as no override.
            return .autoupdatingCurrent
        }
        return Locale(identifier: identifier)
    }
}
