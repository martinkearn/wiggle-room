//
//  SiriPhrasesView.swift
//  WiggleRoom
//

import SwiftUI
import AppIntents

/// Settings page listing what to say to Siri — a reference for the phrases
/// `WiggleRoomShortcuts` registers. The wording here is hand-kept in step
/// with that file (App Shortcut phrases can't be read back at runtime); when
/// adding a phrase there, add it here too.
struct SiriPhrasesView: View {
    private struct Group: Identifiable {
        let title: String
        let footer: String
        let phrases: [String]
        var id: String { title }
    }

    private let groups = [
        Group(
            title: "Check how you're doing",
            footer: "With no tracker named, Siri summarises every active tracker.",
            phrases: [
                "What's my Wiggle Room?",
                "Check my Wiggle Room",
                "How am I doing in Wiggle Room?",
                "Check my tracker in Wiggle Room",
            ]
        ),
        Group(
            title: "Check one tracker",
            footer: "Say the tracker's name exactly as it appears in the app.",
            phrases: [
                "What is my Groceries Wiggle Room?",
                "What is my Wiggle Room in Groceries?",
                "How's Groceries in Wiggle Room?",
                "Check Mileage in Wiggle Room",
            ]
        ),
        Group(
            title: "Log a reading",
            footer: "Manual trackers only. Siri asks which tracker and what value.",
            phrases: [
                "Log a reading in Wiggle Room",
                "Update a tracker in Wiggle Room",
            ]
        ),
    ]

    var body: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: 20) {
            Text("Siri").font(WiggleRoomFont.headline(22, weight: 650))
            Text("Say \"Hey Siri\" followed by any of these.")
                .foregroundStyle(.secondary)
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.title).font(WiggleRoomFont.headline(17, weight: 650))
                    ForEach(group.phrases, id: \.self) { phrase in
                        Label {
                            Text("“\(phrase)”")
                        } icon: {
                            Image(systemName: "waveform").foregroundStyle(TrackerPalette.color(at: 4))
                        }
                    }
                    Text(group.footer).font(.wiggleText(.caption)).foregroundStyle(.secondary)
                }
            }
        }
        #else
        List {
            Section {
                Text("Say \"Hey Siri\" followed by any of these.")
                    .foregroundStyle(.secondary)
            }
            ForEach(groups) { group in
                Section {
                    ForEach(group.phrases, id: \.self) { phrase in
                        Label {
                            Text("“\(phrase)”")
                        } icon: {
                            Image(systemName: "waveform").foregroundStyle(TrackerPalette.color(at: 4))
                        }
                    }
                } header: {
                    Text(group.title)
                        .font(WiggleRoomFont.headline(15, weight: 650))
                } footer: {
                    Text(group.footer)
                }
            }
            Section {
                ShortcutsLink()
            }
        }
        .navigationTitle("Siri")
        #endif
    }
}

#Preview {
    NavigationStack { SiriPhrasesView() }
}
