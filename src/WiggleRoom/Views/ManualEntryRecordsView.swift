//
//  ManualEntryRecordsView.swift
//  WiggleRoom
//

import SwiftData
import SwiftUI

struct ManualEntryRecordsView: View {
    @Environment(TrackerStore.self) private var store
    @Query(filter: #Predicate<ConnectedSource> { $0.providerId == "manual" })
    private var manualSources: [ConnectedSource]

    @State private var isPresentingCleanupConfirmation = false
    @State private var cleanupResult: String?

    var body: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: 16) {
            Text("Manual Entry Records")
                .font(WiggleRoomFont.headline(22, weight: 650))
            ManualEntryRecordsExplanation(recordCount: manualSources.count)
            ForEach(manualSources) { source in
                ManualEntryRecordRow(
                    id: source.id,
                    trackerCount: source.trackers?.count ?? 0,
                    isCanonical: source.persistentModelID == store.manualEntrySource.persistentModelID
                )
                .padding(12)
                .background(.quinary, in: RoundedRectangle(cornerRadius: 12))
            }
            ManualEntryCleanupControls(
                duplicateCount: max(manualSources.count - 1, 0),
                cleanupResult: cleanupResult,
                requestCleanup: { isPresentingCleanupConfirmation = true }
            )
        }
        .confirmationDialog(
            "Run Manual Entry Housekeeping?",
            isPresented: $isPresentingCleanupConfirmation,
            titleVisibility: .visible
        ) {
            Button("Run Housekeeping") {
                cleanUpManualRecords()
            }
        } message: {
            Text("Trackers remain intact. Any duplicate plumbing records are merged into the same canonical record used by your other devices.")
        }
        #else
        List {
            Section {
                ManualEntryRecordsExplanation(recordCount: manualSources.count)
            }
            Section("Records") {
                ForEach(manualSources) { source in
                    ManualEntryRecordRow(
                        id: source.id,
                        trackerCount: source.trackers?.count ?? 0,
                        isCanonical: source.persistentModelID == store.manualEntrySource.persistentModelID
                    )
                }
            }
            ManualEntryCleanupControls(
                duplicateCount: max(manualSources.count - 1, 0),
                cleanupResult: cleanupResult,
                requestCleanup: { isPresentingCleanupConfirmation = true }
            )
        }
        .navigationTitle("Manual Entry Records")
        .inlineNavigationBarIfAvailable()
        .confirmationDialog(
            "Run Manual Entry Housekeeping?",
            isPresented: $isPresentingCleanupConfirmation,
            titleVisibility: .visible
        ) {
            Button("Run Housekeeping") {
                cleanUpManualRecords()
            }
        } message: {
            Text("Trackers remain intact. Any duplicate plumbing records are merged into the same canonical record used by your other devices.")
        }
        #endif
    }
}

private struct ManualEntryRecordsExplanation: View {
    let recordCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent("Plumbing records", value: recordCount.formatted())
            Text("Manual Entry records are internal links used by manual trackers. They are not external connections and normally only one is needed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ManualEntryRecordRow: View {
    let id: UUID
    let trackerCount: Int
    let isCanonical: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(
                    isCanonical ? "Canonical Manual Entry" : "Duplicate Manual Entry",
                    systemImage: isCanonical ? "checkmark.circle.fill" : "doc.on.doc"
                )
                Spacer()
                Text("\(trackerCount) tracker\(trackerCount == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
            }
            Text(id.uuidString)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }
}

private struct ManualEntryCleanupControls: View {
    let duplicateCount: Int
    let cleanupResult: String?
    let requestCleanup: () -> Void

    var body: some View {
        Section("Cleanup") {
            LabeledContent("Duplicate records", value: duplicateCount.formatted())
            if duplicateCount > 0 {
                Button("Run Housekeeping Now…", action: requestCleanup)
            }
            if let cleanupResult {
                Text(cleanupResult)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

extension ManualEntryRecordsView {
    private func cleanUpManualRecords() {
        do {
            let removedCount = try store.consolidateManualEntrySources()
            cleanupResult = removedCount == 0
                ? "No duplicate Manual Entry records were found."
                : "Removed \(removedCount) duplicate Manual Entry record\(removedCount == 1 ? "" : "s")."
        } catch {
            cleanupResult = "Cleanup failed: \(error.localizedDescription)"
        }
    }
}
