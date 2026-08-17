//
//  AppDelegate.swift
//  BODYCam
//
//  Exists to receive notification taps. SwiftUI has no equivalent hook that
//  works on cold launch, so the UNUserNotificationCenter delegate has to live
//  on a UIKit app delegate wired in via @UIApplicationDelegateAdaptor.
//

import UIKit
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Has to be assigned before launch finishes: if the tap is what starts
        // the app, iOS delivers the response immediately afterwards and drops
        // it when no delegate is set yet.
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Tapping a reminder opens the app on that photo or video.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let file = MediaScheduler.mediaFileName(
            fromReminderID: response.notification.request.identifier
        ) {
            DispatchQueue.main.async {
                NotificationRouter.shared.mediaToOpen = file
            }
        }
        completionHandler()
    }

    /// Without this the reminder is swallowed silently whenever the app happens
    /// to be open — no banner and, more importantly, no sound.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}
