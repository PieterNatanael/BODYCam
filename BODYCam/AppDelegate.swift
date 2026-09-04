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

        // register(defaults:) rather than changing the @AppStorage literal in
        // SettingsView alone: PhotoCameraView and VideoCaptureDelegate read
        // this setting via a plain UserDefaults.standard.bool(forKey:) call,
        // not through SettingsView's @AppStorage property — and a raw
        // bool(forKey:) on a key that has never been set returns false no
        // matter what default @AppStorage declares elsewhere, until Settings
        // has actually been opened at least once. A brand new install can
        // easily take its first photo before ever visiting Settings, so that
        // default needs to be in place before ANY view exists, not just
        // SettingsView's own. register(defaults:) does exactly that — and,
        // same as @AppStorage's own default, never overrides a value that has
        // actually been set, so anyone who already chose OFF keeps OFF.
        UserDefaults.standard.register(defaults: ["ShowDateStamp": true])

        return true
    }

    /// Locks the whole interface to portrait while Circle mode is active, so
    /// the tab bar, every button, and all their positions stay completely
    /// still when the phone is physically rotated — Circle mode's control
    /// icons reorient in place instead (see reorientIcon in
    /// CameraPreviewView.swift), the same convention the built in Camera app
    /// uses. Every other mode keeps the normal behaviour declared in the
    /// project's own orientation settings (portrait plus both landscapes,
    /// no upside down on iPhone).
    ///
    /// Read directly from UserDefaults rather than through an @AppStorage:
    /// this delegate method isn't a View and can't hold one, the same
    /// reason PhotoCaptureDelegate and VideoCaptureDelegate read
    /// ShowDateStamp this way instead.
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        let raw = UserDefaults.standard.string(forKey: "CameraDisplayMode")
        if raw == CameraDisplayMode.circle.rawValue {
            return .portrait
        }
        return .allButUpsideDown
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
