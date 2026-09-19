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
    case siri

    var label: String {
        switch self {
        case .general: "General"
        case .connectedSources: "Connected Sources"
        case .siri: "Siri Phrases"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .connectedSources: "point.3.filled.connected.trianglepath.dotted"
        case .siri: "waveform"
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
                ForEach([SettingsPane.general, .connectedSources, .siri], id: \.self) { pane in
                    Label(pane.label, systemImage: pane.systemImage)
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
        case .siri:
            SiriPhrasesView()
        }
    }
}

#Preview {
    SettingsRootView()
        .modelContainer(PreviewData.container)
        .environment(PreviewData.store)
}
#endif
