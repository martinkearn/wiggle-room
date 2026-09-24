//
//  SettingsRootView.swift
//  WiggleRoom
//

#if os(macOS)
import SwiftUI
import SwiftData

private enum SettingsPane: String, Hashable {
    case general
    case connectedSources
    case order
    case transfer
    case siri
    case cloudKit
    case about
    case dangerZone

    var label: String {
        switch self {
        case .general: "General"
        case .connectedSources: "Connected Sources"
        case .order: "Tracker Order"
        case .transfer: "Export & Import"
        case .siri: "Siri Phrases"
        case .cloudKit: "CloudKit Sync"
        case .about: "About"
        case .dangerZone: "Danger Zone"
        }
    }

    var colorIndex: Int {
        switch self {
        case .general: 2
        case .connectedSources: 3
        case .order: 1
        case .transfer: 2
        case .siri: 4
        case .cloudKit: 5
        case .about: 0
        case .dangerZone: 0
        }
    }

    /// Overrides `colorIndex`'s palette lookup for Danger Zone, which needs
    /// a fixed, unmistakably red glyph rather than one of the per-tracker
    /// identity colours every other pane picks from.
    var color: Color? {
        switch self {
        case .dangerZone: WiggleRoomColors.bad
        default: nil
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .connectedSources: "point.3.filled.connected.trianglepath.dotted"
        case .order: "arrow.up.arrow.down"
        case .transfer: "arrow.up.arrow.down.square"
        case .siri: "waveform"
        case .cloudKit: "icloud"
        case .about: "info.circle"
        case .dangerZone: "exclamationmark.triangle.fill"
        }
    }
}

/// macOS Settings window (§7.2): a fixed sidebar of setting categories with
/// their content shown directly alongside it — the sidebar-plus-detail
/// convention modern macOS System Settings itself uses (and Claude's own
/// desktop app Settings window), not the older icon-tab-bar style
/// (`TabView` + `.tabItem`) this app originally shipped with. Replaced
/// 2026-09-18 per explicit design direction to match that convention.
///
/// A plain `HStack` rather than `NavigationSplitView` deliberately — this
/// sidebar is fixed-width and never collapses/resizes, matching System
/// Settings' own non-resizable sidebar, whereas `NavigationSplitView`
/// brings a draggable divider and collapse affordance neither needs.
struct SettingsRootView: View {
    @State private var selection: SettingsPane = .general

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $selection) {
                ForEach([SettingsPane.general, .connectedSources, .order, .transfer, .siri, .cloudKit, .about, .dangerZone], id: \.self) { pane in
                    SettingsLabel(title: pane.label, symbol: pane.systemImage, colorIndex: pane.colorIndex, color: pane.color, size: 24)
                        .tag(pane)
                }
            }
            .listStyle(.sidebar)
            .frame(width: 190)

            Divider()

            ScrollView {
                content
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 640, height: 440)
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .general:
            GeneralSettingsView()
        case .connectedSources:
            ConnectedSourcesView()
        case .order:
            TrackerOrderView()
        case .transfer:
            TrackerTransferView()
        case .siri:
            SiriPhrasesView()
        case .cloudKit:
            CloudSyncDiagnosticsView()
        case .about:
            AboutView()
        case .dangerZone:
            DangerZoneView()
        }
    }
}

#Preview {
    SettingsRootView()
        .modelContainer(PreviewData.container)
        .environment(PreviewData.store)
}
#endif
