//
//  TrackerLiveActivityWidget.swift
//  WiggleRoomWidgets
//

#if os(iOS)
import ActivityKit
import SwiftUI
import WidgetKit

/// Lock Screen / Dynamic Island presentation of a tracker's final-stretch
/// Live Activity (`TrackerLiveActivity`).
struct TrackerLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TrackerActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(context.attributes.name)
                        .font(WiggleRoomFont.headline(16, weight: 650))
                    Spacer()
                    Text(context.attributes.endDate, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(context.state.statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(context.state.difference)
                    .font(.wiggleNumber(.title2, weight: .bold))
                    .foregroundStyle(color(context.state))
            }
            .padding()
            .widgetURL(WiggleRoomDeepLink.url(forTrackerId: context.attributes.trackerId))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.name).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.difference)
                        .font(.wiggleNumber(.headline, weight: .bold))
                        .foregroundStyle(color(context.state))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.statusLine)
                        Spacer()
                        Text(context.attributes.endDate, style: .relative)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "circle.circle").foregroundStyle(color(context.state))
            } compactTrailing: {
                Text(context.state.difference)
                    .font(.wiggleNumber(.caption, weight: .bold))
                    .foregroundStyle(color(context.state))
            } minimal: {
                Image(systemName: "circle.circle").foregroundStyle(color(context.state))
            }
            .widgetURL(WiggleRoomDeepLink.url(forTrackerId: context.attributes.trackerId))
        }
    }

    private func color(_ state: TrackerActivityAttributes.ContentState) -> Color {
        state.isOnPace ? .green : .orange
    }
}
#endif
