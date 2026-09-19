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
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    badge(context.attributes, size: 30)
                    Text(context.attributes.name)
                        .font(WiggleRoomFont.headline(16, weight: 650))
                    Spacer()
                    Text(context.attributes.endDate, style: .relative)
                        .font(.wiggleText(.caption))
                        .foregroundStyle(.secondary)
                }
                Text(context.state.statusLine)
                    .font(.wiggleText(.caption))
                    .foregroundStyle(.secondary)
                Text(context.state.difference)
                    .font(.wiggleNumber(.title2, weight: .bold))
                    .foregroundStyle(color(context.state))
            }
            .padding()
            .activityBackgroundTint(TrackerPalette.color(at: context.attributes.colorIndex ?? 0).opacity(0.18))
            .widgetURL(WiggleRoomDeepLink.url(forTrackerId: context.attributes.trackerId))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        badge(context.attributes, size: 26)
                        Text(context.attributes.name).font(WiggleRoomFont.headline(17, weight: 650)).lineLimit(1)
                    }
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
                    .font(.wiggleText(.caption))
                    .foregroundStyle(.secondary)
                }
            } compactLeading: {
                badge(context.attributes, size: 20)
            } compactTrailing: {
                Text(context.state.difference)
                    .font(.wiggleNumber(.caption, weight: .bold))
                    .foregroundStyle(color(context.state))
            } minimal: {
                badge(context.attributes, size: 20)
            }
            .widgetURL(WiggleRoomDeepLink.url(forTrackerId: context.attributes.trackerId))
        }
    }

    private func color(_ state: TrackerActivityAttributes.ContentState) -> Color {
        state.isOnPace ? WiggleRoomColors.good : WiggleRoomColors.warning
    }

    private func badge(_ attributes: TrackerActivityAttributes, size: CGFloat) -> some View {
        let index = attributes.colorIndex ?? 0
        return WobblyBadge(
            color: TrackerPalette.color(at: index),
            symbol: attributes.glyph ?? "circle.circle",
            seed: Double(index) * 1.3,
            size: size
        )
    }
}
#endif
