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
    var sourceCount = 0
    var latestReadingDate: Date?
    var checkedAt: Date?
    var errorDetails: String?
}

struct CloudSyncDiagnosticsView: View {
    private static let containerIdentifier = "iCloud.martinkearn.WiggleRoom"

    @Environment(\.modelContext) private var modelContext
    @State private var diagnostics = CloudSyncDiagnostics.shared
    @State private var snapshot = CloudSyncSnapshot()
    @State private var isRefreshing = false

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
                sourceCount: snapshot.sourceCount,
                latestReadingDate: snapshot.latestReadingDate
            )
            CloudSyncTechnicalSection(
                containerIdentifier: Self.containerIdentifier,
                checkedAt: snapshot.checkedAt
            )
            CloudSyncRefreshButton(isRefreshing: isRefreshing, refresh: refresh)
        }
        .navigationTitle("CloudKit Sync")
        .task { await refresh() }
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
                sourceCount: snapshot.sourceCount,
                latestReadingDate: snapshot.latestReadingDate
            )
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
        #endif
    }

    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        snapshot.trackerCount = (try? modelContext.fetchCount(FetchDescriptor<Tracker>())) ?? 0
        snapshot.readingCount = (try? modelContext.fetchCount(FetchDescriptor<ValueSnapshot>())) ?? 0
        snapshot.sourceCount = (try? modelContext.fetchCount(FetchDescriptor<ConnectedSource>())) ?? 0

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
    let sourceCount: Int
    let latestReadingDate: Date?

    var body: some View {
        Section("Local data on this device") {
            LabeledContent("Trackers", value: trackerCount.formatted())
            LabeledContent("Readings", value: readingCount.formatted())
            LabeledContent("Connected sources", value: sourceCount.formatted())
            LabeledContent("Latest reading") {
                if let latestReadingDate {
                    Text(latestReadingDate, format: .dateTime.day().month().year().hour().minute())
                } else {
                    Text("None")
                }
            }
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
