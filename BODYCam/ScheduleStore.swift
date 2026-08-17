//
//  ScheduleStore.swift
//  BODYCam
//
//  Tracks which photos and videos currently have an alarm or reminder waiting,
//  so Settings can list them and let one be cancelled.
//
//  iOS is the source of truth for whether something is still scheduled, but it
//  can't tell us *what* it was for: `AlarmManager` hands back only an id,
//  schedule and state, with no way to reach the media behind it. So we keep our
//  own thin record and reconcile it against the live system state on every
//  refresh — anything that has since fired or been cancelled elsewhere simply
//  drops out of the list.
//

import Foundation
import UserNotifications

#if canImport(AlarmKit)
import AlarmKit
#endif

struct ScheduledItem: Identifiable, Codable, Equatable {
    enum Kind: String, Codable {
        case alarm
        case reminder
    }

    /// Alarm UUID string, or the notification request identifier.
    let id: String
    let kind: Kind
    let mediaFileName: String
    let mediaName: String
    let isPhoto: Bool
    let hour: Int
    let minute: Int

    /// Optional purely for backwards compatibility: Swift's synthesized
    /// decoder treats a missing key as an error rather than falling back to a
    /// default, so records written before daily repeat existed would fail to
    /// decode — taking the whole saved list down with them.
    let repeatsDaily: Bool?

    var isDaily: Bool { repeatsDaily == true }

    var displayTime: String {
        var parts = DateComponents()
        parts.hour = hour
        parts.minute = minute
        let date = Calendar.current.date(from: parts) ?? Date()
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

final class ScheduleStore: ObservableObject {
    static let shared = ScheduleStore()

    @Published private(set) var items: [ScheduledItem] = []

    private let key = "BodyCamScheduledAlarmsAndReminders"

    private init() {
        items = load()
    }

    // MARK: Persistence

    private func load() -> [ScheduledItem] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([ScheduledItem].self, from: data) else { return [] }
        return decoded
    }

    private func save(_ list: [ScheduledItem]) {
        guard let data = try? JSONEncoder().encode(list) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    // MARK: Mutation

    func add(_ item: ScheduledItem) {
        DispatchQueue.main.async {
            // Re-scheduling a reminder for the same item reuses its identifier
            // and replaces the pending request, so replace the row rather than
            // ending up with a duplicate.
            var list = self.items.filter { $0.id != item.id }
            list.append(item)
            self.items = Self.sorted(list)
            self.save(self.items)
        }
    }

    func remove(_ item: ScheduledItem) {
        cancelUnderlying(item)
        items = items.filter { $0.id != item.id }
        save(items)
    }

    /// Called when media is deleted from the gallery — a reminder pointing at a
    /// file that no longer exists would fire and then land on nothing.
    func removeAll(forFileName fileName: String) {
        let doomed = items.filter { $0.mediaFileName == fileName }
        guard !doomed.isEmpty else { return }
        doomed.forEach(cancelUnderlying)
        items = items.filter { $0.mediaFileName != fileName }
        save(items)
    }

    private func cancelUnderlying(_ item: ScheduledItem) {
        switch item.kind {
        case .reminder:
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: [item.id])
        case .alarm:
            #if canImport(AlarmKit)
            if #available(iOS 26.0, *), let uuid = UUID(uuidString: item.id) {
                try? AlarmManager.shared.cancel(id: uuid)
            }
            #endif
        }
    }

    // MARK: Reconciliation

    /// Drops anything iOS no longer has scheduled — fired reminders, alarms
    /// stopped from the lock screen, and so on.
    func refresh() {
        let stored = load()
        guard !stored.isEmpty else {
            DispatchQueue.main.async { self.items = [] }
            return
        }

        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            let liveReminders = Set(requests.map { $0.identifier })

            var liveAlarms = Set<String>()
            #if canImport(AlarmKit)
            if #available(iOS 26.0, *) {
                let alarms = (try? AlarmManager.shared.alarms) ?? []
                liveAlarms = Set(alarms.map { $0.id.uuidString })
            }
            #endif

            let kept = stored.filter { item in
                switch item.kind {
                case .reminder: return liveReminders.contains(item.id)
                case .alarm:    return liveAlarms.contains(item.id)
                }
            }

            DispatchQueue.main.async {
                self.items = Self.sorted(kept)
                self.save(self.items)
            }
        }
    }

    private static func sorted(_ list: [ScheduledItem]) -> [ScheduledItem] {
        list.sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
    }
}
