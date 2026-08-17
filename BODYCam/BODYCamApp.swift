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

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
