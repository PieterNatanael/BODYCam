//
//  MediaScheduler.swift
//  BODYCam
//
//  Scheduling a photo or video to resurface later, two ways — they trade off
//  against each other, which is why both exist:
//
//  • Alarm (AlarmKit, iOS 26+) — a real system alarm: full-screen alert that
//    breaks through the silent switch and Focus. Its "View" button opens the
//    app straight to the item.
//
//  • Reminder (UserNotifications, every iOS version) — an ordinary
//    notification. Tapping it opens the app to the item. Respects the silent
//    switch and Focus, but works everywhere.
//
//  Unlike the audio app this pattern came from, the media here is visual, so
//  the notification's *sound* can't be the item itself — a thumbnail is
//  attached instead, and the media is reached by tapping through.
//

import Foundation
import AVFoundation
import UserNotifications
import SwiftUI

#if canImport(AlarmKit)
import AlarmKit
import AppIntents
#endif

// MARK: - Mode

enum ScheduleMode: String, Identifiable {
    /// True system alarm (AlarmKit, iOS 26+). Breaks through silent/Focus.
    case alarm
    /// Notification that opens the item when tapped. All iOS versions.
    case reminder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .alarm:    return "Set as Alarm"
        case .reminder: return "Set as Reminder"
        }
    }

    var systemImage: String {
        switch self {
        case .alarm:    return "alarm.fill"
        case .reminder: return "bell.fill"
        }
    }
}

// MARK: - Alarm Metadata (AlarmKit)

#if canImport(AlarmKit)
@available(iOS 26.0, *)
struct MediaAlarmMetadata: AlarmMetadata {
    init() {}
}

/// Backs the "View" button on the alarm alert.
///
/// AlarmKit runs this as the alert's `secondaryIntent`. It executes inside the
/// app's own process, so it can hand the filename straight to
/// `NotificationRouter` the same way a tapped reminder does.
@available(iOS 26.0, *)
struct ViewMediaIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "View Media"

    /// Without this the intent runs in the background and the user sees
    /// nothing — the whole point is to surface the app on that item.
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Media")
    var fileName: String

    /// The alarm this button belongs to, so View can dismiss it.
    @Parameter(title: "Alarm")
    var alarmID: String

    init() {}
    init(fileName: String, alarmID: String) {
        self.fileName = fileName
        self.alarmID = alarmID
    }

    func perform() async throws -> some IntentResult {
        // View has to dismiss the alarm itself. AlarmKit only treats the Stop
        // button as a dismissal — a `.custom` secondary button runs its intent
        // and leaves the alarm ringing, so the ringtone would otherwise keep
        // blaring while the user looks at the photo.
        if let id = UUID(uuidString: alarmID) {
            try? AlarmManager.shared.stop(id: id)
        }
        let name = fileName
        await MainActor.run {
            NotificationRouter.shared.mediaToOpen = name
        }
        return .result()
    }
}
#endif

// MARK: - Notification Router

/// Carries a tapped reminder into the running UI.
///
/// The tap can arrive before any view exists — tapping a notification is often
/// what launches the app — so the request is parked here and picked up by
/// `GalleryView` once it subscribes. `@Published` replays its current value to
/// new subscribers, which is what makes the cold-launch case work.
final class NotificationRouter: ObservableObject {
    static let shared = NotificationRouter()
    private init() {}

    /// Filename of an item the user asked to see by tapping its reminder.
    @Published var mediaToOpen: String?
}

// MARK: - Scheduler

final class MediaScheduler {
    static let shared = MediaScheduler()
    private init() {}

    /// Whether this device can schedule a true AlarmKit alarm at all.
    static var supportsAlarms: Bool {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) { return true }
        return false
        #else
        return false
        #endif
    }

    enum ScheduleError: LocalizedError {
        case notAuthorized
        case alarmsUnavailable

        var messageKey: String {
            switch self {
            case .notAuthorized:     return "Permission denied. Enable it in iOS Settings."
            case .alarmsUnavailable: return "Alarms need iOS 26 or later."
            }
        }

        var errorDescription: String? { messageKey }
    }

    // MARK: Public entry point

    func schedule(_ item: VideoItem,
                  at date: Date,
                  mode: ScheduleMode,
                  repeatsDaily: Bool,
                  completion: @escaping (Result<Void, Error>) -> Void) {
        switch mode {
        case .reminder:
            scheduleReminder(item, at: date, repeatsDaily: repeatsDaily, completion: completion)
        case .alarm:
            scheduleAlarm(item, at: date, repeatsDaily: repeatsDaily, completion: completion)
        }
    }

    // MARK: Reminder (UserNotifications)

    private func scheduleReminder(_ item: VideoItem,
                                  at date: Date,
                                  repeatsDaily: Bool,
                                  completion: @escaping (Result<Void, Error>) -> Void) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            guard granted else {
                self.finish(.failure(error ?? ScheduleError.notAuthorized), completion)
                return
            }

            let content = UNMutableNotificationContent()
            content.title = item.isPhoto ? "Photo reminder" : "Video reminder"
            content.body = item.displayName
            content.sound = .default

            // Breaks through Focus modes. Unlike AlarmKit this still respects
            // the silent switch, but it's the closest a plain notification gets.
            if #available(iOS 15.0, *) {
                content.interruptionLevel = .timeSensitive
            }

            // A thumbnail so the expanded notification previews the item.
            // Never fatal — a missing image is a lesser failure than no
            // reminder at all.
            if let attachment = Self.makeThumbnailAttachment(for: item) {
                content.attachments = [attachment]
            }

            // Hour+minute only, so the trigger resolves to the next occurrence
            // of that time. Pinning the picked day too would schedule into the
            // past whenever the chosen time has already passed today — and it
            // would also stop `repeats` from meaning "daily".
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: repeatsDaily)
            let request = UNNotificationRequest(
                identifier: Self.reminderID(for: item),
                content: content,
                trigger: trigger
            )

            center.add(request) { error in
                if error == nil {
                    ScheduleStore.shared.add(ScheduledItem(
                        id: request.identifier,
                        kind: .reminder,
                        mediaFileName: item.url.lastPathComponent,
                        mediaName: item.displayName,
                        isPhoto: item.isPhoto,
                        hour: parts.hour ?? 0,
                        minute: parts.minute ?? 0,
                        repeatsDaily: repeatsDaily
                    ))
                }
                self.finish(error.map { .failure($0) } ?? .success(()), completion)
            }
        }
    }

    /// iOS rejects image attachments larger than this.
    private static let maxAttachmentBytes = 10 * 1024 * 1024

    /// Builds the preview attachment from a *throwaway copy*.
    /// `UNNotificationAttachment` takes ownership and moves the file it is
    /// handed into the system attachment store, so passing the real photo
    /// would delete it out of the user's gallery.
    private static func makeThumbnailAttachment(for item: VideoItem) -> UNNotificationAttachment? {
        do {
            let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("bodycam-attach-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            if item.isPhoto {
                let attrs = try? FileManager.default.attributesOfItem(atPath: item.url.path)
                if let size = attrs?[.size] as? Int, size > maxAttachmentBytes { return nil }
                let copy = dir.appendingPathComponent(item.url.lastPathComponent)
                try FileManager.default.copyItem(at: item.url, to: copy)
                return try UNNotificationAttachment(identifier: "media", url: copy, options: nil)
            }

            // Video: attach a still frame rather than the movie itself — far
            // smaller than the 50 MB video cap allows, and it renders the same.
            let asset = AVAsset(url: item.url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 800, height: 800)
            let cg = try generator.copyCGImage(at: CMTimeMake(value: 0, timescale: 60), actualTime: nil)
            guard let jpeg = UIImage(cgImage: cg).jpegData(compressionQuality: 0.8) else { return nil }
            let thumbURL = dir.appendingPathComponent("thumb.jpg")
            try jpeg.write(to: thumbURL)
            return try UNNotificationAttachment(identifier: "media", url: thumbURL, options: nil)
        } catch {
            return nil
        }
    }

    /// The item's filename is carried in the notification identifier so a tap
    /// can be resolved back to the right file however long later — the
    /// notification sits in Notification Center until dismissed. The filename
    /// rather than a full URL, because the app container path changes between
    /// launches and updates.
    private static let reminderIDPrefix = "bodycam.reminder."

    static func reminderID(for item: VideoItem) -> String {
        reminderIDPrefix + item.url.lastPathComponent
    }

    static func mediaFileName(fromReminderID id: String) -> String? {
        guard id.hasPrefix(reminderIDPrefix) else { return nil }
        return String(id.dropFirst(reminderIDPrefix.count))
    }

    // MARK: Alarm (AlarmKit)

    private func scheduleAlarm(_ item: VideoItem,
                               at date: Date,
                               repeatsDaily: Bool,
                               completion: @escaping (Result<Void, Error>) -> Void) {
        #if canImport(AlarmKit)
        guard #available(iOS 26.0, *) else {
            finish(.failure(ScheduleError.alarmsUnavailable), completion)
            return
        }

        Task {
            do {
                let manager = AlarmManager.shared
                var state = manager.authorizationState
                if state == .notDetermined {
                    state = try await manager.requestAuthorization()
                }
                guard state == .authorized else {
                    self.finish(.failure(ScheduleError.notAuthorized), completion)
                    return
                }

                let title = LocalizedStringResource(stringLiteral: item.displayName)

                // Second button on the alert, beside Stop. `.custom` is what
                // routes it to our `secondaryIntent` — the other behaviour,
                // `.countdown`, would turn it into a snooze button instead.
                let viewButton = AlarmButton(
                    text: LocalizedStringResource("View"),
                    textColor: .white,
                    systemImageName: "eye.fill"
                )

                let alert: AlarmPresentation.Alert
                if #available(iOS 26.1, *) {
                    alert = AlarmPresentation.Alert(
                        title: title,
                        secondaryButton: viewButton,
                        secondaryButtonBehavior: .custom
                    )
                } else {
                    // 26.0 requires an explicit stop button; 26.1 deprecated it
                    // in favour of a system-provided one.
                    alert = AlarmPresentation.Alert(
                        title: title,
                        stopButton: AlarmButton(
                            text: LocalizedStringResource("Stop"),
                            textColor: .white,
                            systemImageName: "stop.fill"
                        ),
                        secondaryButton: viewButton,
                        secondaryButtonBehavior: .custom
                    )
                }

                let attributes = AlarmAttributes<MediaAlarmMetadata>(
                    presentation: AlarmPresentation(alert: alert),
                    metadata: MediaAlarmMetadata(),
                    tintColor: .accentColor
                )

                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                // AlarmKit has no "daily" case — recurrence is expressed per
                // weekday, so every day means listing all seven.
                let recurrence: Alarm.Schedule.Relative.Recurrence = repeatsDaily
                    ? .weekly([.sunday, .monday, .tuesday, .wednesday, .thursday, .friday, .saturday])
                    : .never
                let schedule = Alarm.Schedule.relative(
                    .init(time: .init(hour: parts.hour ?? 0, minute: parts.minute ?? 0),
                          repeats: recurrence)
                )

                // Generated up front so the View button's intent can carry the
                // same id back and dismiss this exact alarm.
                let alarmID = UUID()
                _ = try await manager.schedule(
                    id: alarmID,
                    configuration: AlarmManager.AlarmConfiguration.alarm(
                        schedule: schedule,
                        attributes: attributes,
                        secondaryIntent: ViewMediaIntent(
                            fileName: item.url.lastPathComponent,
                            alarmID: alarmID.uuidString
                        )
                    )
                )

                ScheduleStore.shared.add(ScheduledItem(
                    id: alarmID.uuidString,
                    kind: .alarm,
                    mediaFileName: item.url.lastPathComponent,
                    mediaName: item.displayName,
                    isPhoto: item.isPhoto,
                    hour: parts.hour ?? 0,
                    minute: parts.minute ?? 0,
                    repeatsDaily: repeatsDaily
                ))
                self.finish(.success(()), completion)
            } catch {
                self.finish(.failure(error), completion)
            }
        }
        #else
        finish(.failure(ScheduleError.alarmsUnavailable), completion)
        #endif
    }

    // MARK: Helpers

    private func finish(_ result: Result<Void, Error>,
                        _ completion: @escaping (Result<Void, Error>) -> Void) {
        DispatchQueue.main.async { completion(result) }
    }
}
