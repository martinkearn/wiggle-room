//
//  CloudSyncDiagnosticsView.swift
//  WiggleRoom
//

import CloudKit
import Observation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class CloudSyncDiagnostics {
    enum PersistenceMode: Equatable {
        case starting
        case cloudKit
        case localFallback(String)
    }

    static let shared = CloudSyncDiagnostics()

    private(set) var persistenceMode: PersistenceMode = .starting

    private init() {}

    func recordCloudKitStore() {
        persistenceMode = .cloudKit
    }

    func recordLocalFallback(error: any Error) {
        persistenceMode = .localFallback(error.localizedDescription)
    }
}

private struct CloudSyncSnapshot: Equatable {
    var accountStatus = "Not checked"
    var reachability = "Not checked"
    var zoneCount: Int?
    var trackerCount = 0
    var readingCount = 0
    var externalSourceCount = 0
    var manualSourceCount = 0
    var latestReadingDate: Date?
    var checkedAt: Date?
    var errorDetails: String?
}

struct CloudSyncDiagnosticsView: View {
    private static let containerIdentifier = "iCloud.martinkearn.WiggleRoom"

    @Environment(\.modelContext) private var modelContext
    @Environment(TrackerStore.self) private var store
    @Query(filter: #Predicate<ConnectedSource> { $0.providerId == "manual" })
    private var manualSources: [ConnectedSource]
    @State private var diagnostics = CloudSyncDiagnostics.shared
    @State private var snapshot = CloudSyncSnapshot()
    @State private var isRefreshing = false
    @State private var isPresentingManualCleanupConfirmation = false
    @State private var manualCleanupResult: String?

    var body: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: 20) {
            CloudSyncStatusSection(
                persistenceMode: diagnostics.persistenceMode,
                accountStatus: snapshot.accountStatus,
                reachability: snapshot.reachability,
                zoneCount: snapshot.zoneCount,
                errorDetails: snapshot.errorDetails
            )
            CloudSyncLocalDataSection(
                trackerCount: snapshot.trackerCount,
                readingCount: snapshot.readingCount,
                externalSourceCount: snapshot.externalSourceCount,
                manualSourceCount: snapshot.manualSourceCount,
                latestReadingDate: snapshot.latestReadingDate,
                cleanupResult: manualCleanupResult,
                requestCleanup: { isPresentingManualCleanupConfirmation = true }
            )
            CloudSyncManualRecordsSection(manualSources: manualSources, canonicalID: store.manualEntrySource.persistentModelID)
            CloudSyncTechnicalSection(
                containerIdentifier: Self.containerIdentifier,
                checkedAt: snapshot.checkedAt
            )
            CloudSyncRefreshButton(isRefreshing: isRefreshing, refresh: refresh)
        }
        .navigationTitle("CloudKit Sync")
        .task { await refresh() }
        .confirmationDialog(
            "Remove Duplicate Manual Records?",
            isPresented: $isPresentingManualCleanupConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clean Up Records", role: .destructive) {
                Task { await cleanUpManualRecords() }
            }
        } message: {
            Text("Trackers will be moved to one Manual Entry record before the redundant records are deleted. This cleanup syncs to your other devices.")
        }
        #else
        List {
            CloudSyncStatusSection(
                persistenceMode: diagnostics.persistenceMode,
                accountStatus: snapshot.accountStatus,
                reachability: snapshot.reachability,
                zoneCount: snapshot.zoneCount,
                errorDetails: snapshot.errorDetails
            )
            CloudSyncLocalDataSection(
                trackerCount: snapshot.trackerCount,
                readingCount: snapshot.readingCount,
                externalSourceCount: snapshot.externalSourceCount,
                manualSourceCount: snapshot.manualSourceCount,
                latestReadingDate: snapshot.latestReadingDate,
                cleanupResult: manualCleanupResult,
                requestCleanup: { isPresentingManualCleanupConfirmation = true }
            )
            CloudSyncManualRecordsSection(manualSources: manualSources, canonicalID: store.manualEntrySource.persistentModelID)
            CloudSyncTechnicalSection(
                containerIdentifier: Self.containerIdentifier,
                checkedAt: snapshot.checkedAt
            )
            CloudSyncRefreshButton(isRefreshing: isRefreshing, refresh: refresh)
        }
        .navigationTitle("CloudKit Sync")
        .inlineNavigationBarIfAvailable()
        .task { await refresh() }
        .refreshable { await refresh() }
        .confirmationDialog(
            "Remove Duplicate Manual Records?",
            isPresented: $isPresentingManualCleanupConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clean Up Records", role: .destructive) {
                Task { await cleanUpManualRecords() }
            }
        } message: {
            Text("Trackers will be moved to one Manual Entry record before the redundant records are deleted. This cleanup syncs to your other devices.")
        }
        #endif
    }

    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        snapshot.trackerCount = (try? modelContext.fetchCount(FetchDescriptor<Tracker>())) ?? 0
        snapshot.readingCount = (try? modelContext.fetchCount(FetchDescriptor<ValueSnapshot>())) ?? 0
        let sources = (try? modelContext.fetch(FetchDescriptor<ConnectedSource>())) ?? []
        snapshot.externalSourceCount = sources.count { $0.providerId != "manual" }
        snapshot.manualSourceCount = sources.count { $0.providerId == "manual" }

        var latestReadingDescriptor = FetchDescriptor<ValueSnapshot>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        latestReadingDescriptor.fetchLimit = 1
        snapshot.latestReadingDate = try? modelContext.fetch(latestReadingDescriptor).first?.date

        let container = CKContainer(identifier: Self.containerIdentifier)
        do {
            let status = try await container.accountStatus()
            snapshot.accountStatus = accountStatusDescription(status)

            guard status == .available else {
                snapshot.reachability = "Unavailable"
                snapshot.zoneCount = nil
                snapshot.errorDetails = nil
                snapshot.checkedAt = .now
                return
            }

            let zones = try await container.privateCloudDatabase.allRecordZones()
            snapshot.reachability = "Connected"
            snapshot.zoneCount = zones.count
            snapshot.errorDetails = nil
        } catch {
            snapshot.reachability = "Connection failed"
            snapshot.zoneCount = nil
            snapshot.errorDetails = error.localizedDescription
        }
        snapshot.checkedAt = .now
    }

    private func cleanUpManualRecords() async {
        do {
            let removedCount = try store.consolidateManualEntrySources()
            manualCleanupResult = removedCount == 0
                ? "No duplicate Manual Entry records were found."
                : "Removed \(removedCount) duplicate Manual Entry record\(removedCount == 1 ? "" : "s")."
        } catch {
            manualCleanupResult = "Cleanup failed: \(error.localizedDescription)"
        }
        await refresh()
    }

    private func accountStatusDescription(_ status: CKAccountStatus) -> String {
        switch status {
        case .available:
            "Available"
        case .noAccount:
            "No iCloud account"
        case .restricted:
            "Restricted"
        case .couldNotDetermine:
            "Could not determine"
        case .temporarilyUnavailable:
            "Temporarily unavailable"
        @unknown default:
            "Unknown"
        }
    }
}

private struct CloudSyncStatusSection: View {
    let persistenceMode: CloudSyncDiagnostics.PersistenceMode
    let accountStatus: String
    let reachability: String
    let zoneCount: Int?
    let errorDetails: String?

    var body: some View {
        Section("Status") {
            LabeledContent("Storage mode", value: storageModeDescription)
            LabeledContent("iCloud account", value: accountStatus)
            LabeledContent("CloudKit", value: reachability)
            if let zoneCount {
                LabeledContent("Private database zones", value: zoneCount.formatted())
            }
            if let details = fallbackDetails {
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            if let errorDetails {
                Text(errorDetails)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
    }

    private var storageModeDescription: String {
        switch persistenceMode {
        case .starting:
            "Starting"
        case .cloudKit:
            "CloudKit enabled"
        case .localFallback:
            "Local only (fallback)"
        }
    }

    private var fallbackDetails: String? {
        if case let .localFallback(message) = persistenceMode {
            return message
        }
        return nil
    }
}

private struct CloudSyncLocalDataSection: View {
    let trackerCount: Int
    let readingCount: Int
    let externalSourceCount: Int
    let manualSourceCount: Int
    let latestReadingDate: Date?
    let cleanupResult: String?
    let requestCleanup: () -> Void

    var body: some View {
        Section("Local data on this device") {
            LabeledContent("Trackers", value: trackerCount.formatted())
            LabeledContent("Readings", value: readingCount.formatted())
            LabeledContent("External connected sources", value: externalSourceCount.formatted())
            LabeledContent("Manual Entry plumbing records", value: manualSourceCount.formatted())
            LabeledContent("Duplicate manual records", value: max(manualSourceCount - 1, 0).formatted())
            LabeledContent("Latest reading") {
                if let latestReadingDate {
                    Text(latestReadingDate, format: .dateTime.day().month().year().hour().minute())
                } else {
                    Text("None")
                }
            }
            if manualSourceCount > 1 {
                Button("Clean Up Manual Records…", role: .destructive, action: requestCleanup)
            }
            if let cleanupResult {
                Text(cleanupResult)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct CloudSyncManualRecordsSection: View {
    let manualSources: [ConnectedSource]
    let canonicalID: PersistentIdentifier

    var body: some View {
        Section("Manual Entry Records") {
            Text("Manual Entry records are internal links used by manual trackers. They are not external connections and normally only one is needed.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(manualSources) { source in
                CloudSyncManualRecordRow(
                    id: source.id,
                    trackerCount: source.trackers?.count ?? 0,
                    isCanonical: source.persistentModelID == canonicalID
                )
            }
        }
    }
}

private struct CloudSyncManualRecordRow: View {
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

private struct CloudSyncTechnicalSection: View {
    let containerIdentifier: String
    let checkedAt: Date?

    var body: some View {
        Section("Technical details") {
            LabeledContent("Container") {
                Text(containerIdentifier)
                    .textSelection(.enabled)
            }
            LabeledContent("Environment", value: "Production in TestFlight")
            LabeledContent("Last health check") {
                if let checkedAt {
                    Text(checkedAt, format: .dateTime.hour().minute().second())
                } else {
                    Text("Never")
                }
            }
            Text("CloudKit does not expose an exact last-sync-completed time for SwiftData. The health check confirms account and database access; local counts update when imported records reach this device.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct CloudSyncRefreshButton: View {
    let isRefreshing: Bool
    let refresh: () async -> Void

    var body: some View {
        Section {
            Button {
                Task { await refresh() }
            } label: {
                if isRefreshing {
                    Label("Checking…", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                } else {
                    Label("Check Now", systemImage: "arrow.clockwise")
                }
            }
            .disabled(isRefreshing)
        }
    }
}
