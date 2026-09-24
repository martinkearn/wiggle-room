import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct TrackerTransferView: View {
    @Environment(TrackerStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Query private var trackers: [Tracker]
    @Query(filter: #Predicate<ConnectedSource> { $0.providerId != "manual" })
    private var connectedSources: [ConnectedSource]

    @State private var exportDocument: TrackerArchiveDocument?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var pendingArchive: TrackerArchive?
    @State private var sourceChoices: [UUID: String] = [:]
    @State private var message: TransferMessage?

    var body: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: 20) {
            Text("Export & Import")
                .font(WiggleRoomFont.headline(22, weight: 650))
            transferControls
            Spacer()
        }
        #else
        List {
            Section {
                transferControls
            } footer: {
                Text("Exports include every tracker setting and reading. Connected-source credentials are never included.")
            }
        }
        .navigationTitle("Export & Import")
        .inlineNavigationBarIfAvailable()
        #endif
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "Wiggle Room Trackers"
        ) { result in
            if case .failure(let error) = result {
                message = TransferMessage(title: "Export Failed", detail: error.localizedDescription)
            }
            exportDocument = nil
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            handleImportSelection(result)
        }
        .sheet(item: $pendingArchive) { archive in
            importReview(for: archive)
        }
        .alert(item: $message) { message in
            Alert(
                title: Text(message.title),
                message: Text(message.detail),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    @ViewBuilder
    private var transferControls: some View {
        Button {
            do {
                exportDocument = TrackerArchiveDocument(
                    data: try TrackerArchiveService.encode(
                        TrackerArchiveService.makeArchive(trackers: trackers)
                    )
                )
                isExporting = true
            } catch {
                message = TransferMessage(title: "Export Failed", detail: error.localizedDescription)
            }
        } label: {
            Label("Export All Trackers", systemImage: "square.and.arrow.up")
        }
        .disabled(trackers.isEmpty)

        Button {
            isImporting = true
        } label: {
            Label("Import Trackers", systemImage: "square.and.arrow.down")
        }

        #if os(macOS)
        Text("Exports include every tracker setting and reading. Connected-source credentials are never included.")
            .font(.wiggleText(.caption))
            .foregroundStyle(.secondary)
        #endif
    }

    private func importReview(for archive: TrackerArchive) -> some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Trackers", value: "\(archive.trackers.count)")
                    LabeledContent("Exported", value: archive.exportedAt.formatted())
                }

                if !archive.externalSources.isEmpty {
                    Section {
                        ForEach(archive.externalSources) { archivedSource in
                            let matchingSources = connectedSources.filter {
                                $0.providerId == archivedSource.providerId
                            }
                            Picker(archivedSource.displayName, selection: choiceBinding(for: archivedSource.id)) {
                                Text("Choose…").tag("")
                                ForEach(matchingSources) { source in
                                    Text(source.displayName).tag(source.id.uuidString)
                                }
                                Text("Import Read Only").tag("read-only")
                            }

                            if matchingSources.isEmpty {
                                Text("No \(archivedSource.providerId.capitalized) source is connected. Create one in Connected Sources, or choose Import Read Only and connect the tracker later from Edit Tracker.")
                                    .font(.wiggleText(.caption))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("Connected Sources")
                    } footer: {
                        Text("For privacy, source credentials are not stored in an export. Choose a source of the same type for each imported connection.")
                    }
                }
            }
            .navigationTitle("Review Import")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        pendingArchive = nil
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        performImport(archive)
                    }
                    .disabled(archive.externalSources.contains {
                        sourceChoices[$0.id, default: ""].isEmpty
                    })
                }
            }
        }
        .frame(minWidth: 420, minHeight: 360)
    }

    private func choiceBinding(for sourceId: UUID) -> Binding<String> {
        Binding(
            get: { sourceChoices[sourceId, default: ""] },
            set: { sourceChoices[sourceId] = $0 }
        )
    }

    private func handleImportSelection(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            let archive = try TrackerArchiveService.decode(Data(contentsOf: url))
            guard !archive.trackers.isEmpty else {
                message = TransferMessage(title: "Nothing to Import", detail: "This archive contains no trackers.")
                return
            }
            sourceChoices = [:]
            for archivedSource in archive.externalSources {
                let matches = connectedSources.filter {
                    $0.providerId == archivedSource.providerId
                }
                if matches.count == 1 {
                    sourceChoices[archivedSource.id] = matches[0].id.uuidString
                }
            }
            pendingArchive = archive
        } catch {
            message = TransferMessage(title: "Import Failed", detail: error.localizedDescription)
        }
    }

    private func performImport(_ archive: TrackerArchive) {
        let mappings = Dictionary(
            uniqueKeysWithValues: archive.externalSources.compactMap { archivedSource in
                guard let choice = sourceChoices[archivedSource.id],
                      let sourceId = UUID(uuidString: choice),
                      let source = connectedSources.first(where: { $0.id == sourceId })
                else { return nil }
                return (archivedSource.id, source)
            }
        )

        do {
            let count = try TrackerArchiveService.importArchive(
                archive,
                sourceMappings: mappings,
                store: store,
                modelContext: modelContext
            )
            let readOnlyCount = archive.trackers.filter { tracker in
                guard let sourceId = tracker.sourceId,
                      archive.externalSources.contains(where: { $0.id == sourceId })
                else { return false }
                return mappings[sourceId] == nil
            }.count
            pendingArchive = nil
            let suffix = readOnlyCount == 0
                ? ""
                : " \(readOnlyCount) imported read-only; connect a source from Edit Tracker."
            message = TransferMessage(
                title: "Import Complete",
                detail: "Imported \(count) tracker\(count == 1 ? "" : "s").\(suffix)"
            )
        } catch {
            pendingArchive = nil
            message = TransferMessage(title: "Import Failed", detail: error.localizedDescription)
        }
    }
}

private struct TransferMessage: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
}

#Preview {
    NavigationStack { TrackerTransferView() }
        .modelContainer(PreviewData.container)
        .environment(PreviewData.store)
}
