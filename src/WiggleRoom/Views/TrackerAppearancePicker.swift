//
//  TrackerAppearancePicker.swift
//  WiggleRoom
//

import SwiftUI

/// The "Colour & glyph" section of Add/Edit Tracker: a live preview badge,
/// eight wobbly colour blobs and a grid of glyphs. Purely presentational —
/// the chosen values are saved on the tracker like any other field.
struct TrackerAppearancePicker: View {
    @Binding var colorIndex: Int
    /// Empty means "the default glyph for this tracker's unit".
    @Binding var glyph: String
    let defaultGlyph: String

    private let colorColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
    private let glyphColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)

    var body: some View {
        Section {
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    WobblyBadge(
                        color: TrackerPalette.color(at: colorIndex),
                        symbol: glyph.isEmpty ? defaultGlyph : glyph,
                        seed: Double(colorIndex) * 1.3,
                        size: 64
                    )
                    Text(TrackerPalette.name(at: colorIndex))
                        .font(.wiggleText(.caption, weight: .bold))
                        .foregroundStyle(TrackerPalette.color(at: colorIndex))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(TrackerPalette.color(at: colorIndex).opacity(0.16), in: Capsule())
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.6), value: colorIndex)
                Spacer()
            }
            .listRowBackground(Color.clear)

            LazyVGrid(columns: colorColumns, spacing: 14) {
                ForEach(TrackerPalette.all) { entry in
                    Button {
                        colorIndex = entry.id
                    } label: {
                        ZStack {
                            BlobShape(seed: Double(entry.id) * 1.3)
                                .fill(entry.color)
                            if entry.id == colorIndex {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(height: 44)
                        .padding(3)
                        .overlay(
                            BlobShape(seed: Double(entry.id) * 1.3)
                                .stroke(entry.id == colorIndex ? Color.primary : .clear, lineWidth: 2.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(entry.name)
                    .accessibilityAddTraits(entry.id == colorIndex ? .isSelected : [])
                }
            }
            .padding(.vertical, 6)

            LazyVGrid(columns: glyphColumns, spacing: 8) {
                ForEach(Array(TrackerPalette.glyphs.enumerated()), id: \.element) { index, symbol in
                    let isSelected = glyph == symbol
                    Button {
                        glyph = isSelected ? "" : symbol
                    } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(isSelected ? .white : .secondary)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(
                                isSelected ? TrackerPalette.color(at: colorIndex) : Color.secondary.opacity(0.12),
                                in: WobblyCard.shape(index, scale: 0.6)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(symbol)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Colour & Glyph")
                .font(WiggleRoomFont.headline(15, weight: 650))
        } footer: {
            Text("Pick a colour and icon to spot this tracker at a glance. The rings still show how it's doing.")
        }
    }
}
