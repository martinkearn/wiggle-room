//
//  CompletedBadge.swift
//  WiggleRoom
//

import SwiftUI

/// A small "Completed" pill — shared across the tracker list, the dashboard,
/// widgets, and complications so every surface a completed tracker can
/// appear on marks it identically rather than each inventing its own label.
struct CompletedBadge: View {
    var body: some View {
        Text("Completed")
            .font(.wiggleText(.caption2, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.secondary.opacity(0.15), in: Capsule())
    }
}

#Preview {
    CompletedBadge()
        .padding()
}
