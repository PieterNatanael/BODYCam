//
//  ScheduledListSheet.swift
//  BODYCam
//
//  Lists every alarm and reminder currently waiting, and lets one be cancelled.
//  Reached from Settings — a reminder you can't find or cancel is worse than no
//  reminder at all.
//

import SwiftUI

struct ScheduledListSheet: View {
    @ObservedObject var store: ScheduleStore

    @Environment(\.presentationMode) private var presentationMode

    var body: some View {
        NavigationView {
            Group {
                if store.items.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "alarm")
                            .font(.system(size: 34)).foregroundColor(.secondary)
                        Text("Nothing scheduled")
                            .font(.subheadline).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(store.items) { item in
                            HStack(spacing: 12) {
                                Image(systemName: item.kind == .alarm ? "alarm.fill" : "bell.fill")
                                    .foregroundColor(.accentColor)
                                    .frame(width: 22)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.mediaName)
                                        .lineLimit(1)
                                    HStack(spacing: 4) {
                                        Text(item.kind == .alarm ? "Alarm" : "Reminder")
                                        Text("·")
                                        Text(item.isDaily ? "Daily" : "Once")
                                    }
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                }

                                Spacer()

                                Text(item.displayTime)
                                    .font(.callout.monospacedDigit())
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                        .onDelete { offsets in
                            offsets.map { store.items[$0] }.forEach(store.remove)
                        }
                    }
                }
            }
            .navigationTitle("Alarms & Reminders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { presentationMode.wrappedValue.dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !store.items.isEmpty { EditButton() }
                }
            }
        }
        .navigationViewStyle(.stack)
        .preferredColorScheme(.dark)
        .onAppear { store.refresh() }
    }
}
