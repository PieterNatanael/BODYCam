//
//  ScheduleSheet.swift
//  BODYCam
//
//  Time picker for scheduling a photo or video as either a true alarm
//  (AlarmKit) or a reminder notification. Both modes share this sheet; the copy
//  and the warnings change to match what each one can actually do.
//
//  Section header/footer use the `Section(footer:content:)` form rather than
//  the trailing-closure `Section { } footer: { }` syntax, which is iOS 15+ —
//  this app still deploys to iOS 14.
//

import SwiftUI

struct ScheduleSheet: View {
    let item: VideoItem
    let mode: ScheduleMode
    let onFinished: () -> Void

    @Environment(\.presentationMode) private var presentationMode

    @State private var time = Date()
    @State private var repeatsDaily = false
    @State private var isWorking = false
    @State private var didSchedule = false
    @State private var errorMessage: String?

    private var alarmUnsupported: Bool {
        mode == .alarm && !MediaScheduler.supportsAlarms
    }

    // Resolved before being interpolated into the sentences below — a plain
    // Swift String interpolated into a LocalizedStringKey is inserted
    // verbatim as data, not translated just because it happens to hold an
    // English word. Bundle.appPreferred rather than the bare
    // NSLocalizedString function so this respects an in-app language
    // override too, not just the device's own system language.
    private var mediaTypeWord: String {
        item.isPhoto
            ? Bundle.appPreferred.localizedString(forKey: "photo", value: nil, table: nil)
            : Bundle.appPreferred.localizedString(forKey: "video", value: nil, table: nil)
    }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: item.isPhoto ? "photo.fill" : "video.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary)
                            .frame(width: 26)
                        Text(item.displayName)
                            .font(.subheadline)
                    }
                    .padding(.vertical, 2)
                }

                Section(footer: Text(repeatsDaily
                                     ? "Fires at this time every day until you cancel it."
                                     : "Fires once, at the next time this comes around.")) {
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                        .disabled(alarmUnsupported)

                    Toggle("Repeat daily", isOn: $repeatsDaily)
                        .disabled(alarmUnsupported)
                }

                Section(header: Text("How this works")) {
                    if alarmUnsupported {
                        Label {
                            Text("Alarms need iOS 26 or later. Use Set as Reminder instead, it still opens this item when you tap it.")
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                        }
                    } else if mode == .alarm {
                        Label {
                            Text("Rings with the iOS alarm sound, breaking through silent mode and Focus.")
                        } icon: {
                            Image(systemName: "alarm.fill")
                        }
                        Label {
                            Text("Tap View on the alarm to open this \(mediaTypeWord).")
                        } icon: {
                            Image(systemName: "eye.fill")
                        }
                    } else {
                        Label {
                            Text("Tap the notification to open this \(mediaTypeWord).")
                        } icon: {
                            Image(systemName: "hand.tap.fill")
                        }
                        Label {
                            Text("Follows your silent switch and Focus settings.")
                        } icon: {
                            Image(systemName: "bell.fill")
                        }
                    }
                }

                if let errorMessage = errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }

                Section {
                    Button {
                        submit()
                    } label: {
                        HStack {
                            Spacer()
                            if isWorking {
                                ProgressView()
                            } else if didSchedule {
                                Label("Scheduled", systemImage: "checkmark")
                            } else {
                                Text("Schedule")
                            }
                            Spacer()
                        }
                    }
                    .disabled(alarmUnsupported || isWorking || didSchedule)
                }
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { presentationMode.wrappedValue.dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
        .preferredColorScheme(.dark)
    }

    private func submit() {
        errorMessage = nil
        isWorking = true
        MediaScheduler.shared.schedule(item, at: time, mode: mode, repeatsDaily: repeatsDaily) { result in
            isWorking = false
            switch result {
            case .success:
                didSchedule = true
                // Brief confirmation before closing.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    presentationMode.wrappedValue.dismiss()
                    onFinished()
                }
            case .failure(let error):
                errorMessage = (error as? MediaScheduler.ScheduleError)?.messageKey
                    ?? error.localizedDescription
            }
        }
    }
}
