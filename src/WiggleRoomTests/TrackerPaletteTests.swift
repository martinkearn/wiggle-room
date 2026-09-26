//
//  TrackerPaletteTests.swift
//  WiggleRoomTests
//

import XCTest
import SwiftUI
@testable import WiggleRoom

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Guards the rule behind `TrackerPalette.Entry.reference`: a colour drawn
/// immediately against a status colour — the chart's pace line, the rings'
/// unfilled track, the pace figure card — must not be a status hue itself,
/// or a green tracker's yardstick reads as "ahead of pace" and a red one's
/// as "behind".
///
/// The audit that produced the five stand-ins is written down here rather
/// than only in a comment, because the failure it prevents is silent: adding
/// a thirteenth palette colour, or re-tuning a status colour, can put the two
/// back into the same hue family without anything else in the app noticing.
final class TrackerPaletteTests: XCTestCase {

    /// The three status colours that can be drawn on a ring or a chart.
    /// `WiggleRoomColors.error` is deliberately absent: it only ever styles
    /// text, so a tracker colour near it cannot be misread as a status.
    private var statusColors: [(name: String, color: Color)] {
        [
            ("good", WiggleRoomColors.good),
            ("warning", WiggleRoomColors.warning),
            ("bad", WiggleRoomColors.bad),
        ]
    }

    /// Degrees of hue that must separate a reference colour from every status
    /// colour. Chosen to sit in the gap the audit found rather than as a round
    /// number: before they were given stand-ins, Peach sat 5° from red, Cherry
    /// 8°, Sunshine 9°, Toffee 10° and Forest 13°, while the closest colour
    /// judged clear enough to keep — Lagoon's cyan against green — sits at
    /// 26°, and every stand-in clears 42°. Anything under this threshold is
    /// therefore a colour that differs from a status colour in shade alone.
    private let minimumHueSeparation: Double = 20

    /// Hue is meaningless for a near-neutral colour, and a near-neutral colour
    /// cannot be mistaken for a saturated status one, so those are exempt.
    /// Slate is the only palette entry this skips.
    private let neutralSaturationCeiling: Double = 0.20

    func testReferenceColorsAreClearOfEveryStatusHue() {
        for entry in TrackerPalette.all {
            for appearance in Appearance.allCases {
                guard let reference = Self.hueAndSaturation(of: entry.reference, in: appearance) else {
                    XCTFail("Could not resolve \(entry.name)'s reference colour in \(appearance).")
                    continue
                }
                guard reference.saturation >= neutralSaturationCeiling else { continue }

                for status in statusColors {
                    guard let statusHue = Self.hueAndSaturation(of: status.color, in: appearance) else {
                        XCTFail("Could not resolve the \(status.name) status colour in \(appearance).")
                        continue
                    }
                    let separation = Self.hueSeparation(reference.hue, statusHue.hue)
                    XCTAssertGreaterThanOrEqual(
                        separation,
                        minimumHueSeparation,
                        """
                        \(entry.name)'s reference colour is \(Int(separation.rounded()))° from the \
                        \(status.name) status colour in \(appearance), which is too close to tell \
                        apart where the two are drawn against each other. Give the entry a \
                        `referenceLight`/`referenceDark` stand-in in `TrackerPalette`.
                        """
                    )
                }
            }
        }
    }

    /// The identity colours are left alone by design — several of them are
    /// status hues on purpose, because that is what the user picked — so this
    /// only checks that the two values are wired up distinctly: every entry
    /// that needs a stand-in has one, and no other entry was given one.
    func testOnlyStatusHuedEntriesCarryAStandIn() {
        var standIns: [String] = []
        for entry in TrackerPalette.all where !Self.isSameColor(entry.color, entry.reference) {
            standIns.append(entry.name)
        }
        XCTAssertEqual(
            standIns,
            ["Peach", "Toffee", "Forest", "Sunshine", "Cherry"],
            "The set of palette entries needing a status-safe stand-in has changed."
        )
    }

    // MARK: - Colour resolution

    enum Appearance: CaseIterable, CustomStringConvertible {
        case light, dark

        var description: String {
            switch self {
            case .light: "light mode"
            case .dark: "dark mode"
            }
        }
    }

    /// Resolves a (possibly appearance-dependent) `Color` for one appearance
    /// and returns its hue in degrees plus its saturation. Goes through the
    /// platform colour types rather than reading the palette's raw values, so
    /// what is measured is what actually gets drawn, `Color.dynamic` included.
    private static func hueAndSaturation(of color: Color, in appearance: Appearance) -> Resolved? {
        #if canImport(UIKit)
        let traits = UITraitCollection(userInterfaceStyle: appearance == .dark ? .dark : .light)
        let resolved = UIColor(color).resolvedColor(with: traits)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        guard resolved.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else {
            return nil
        }
        return Resolved(hue: Double(hue) * 360, saturation: Double(saturation), brightness: Double(brightness))
        #elseif canImport(AppKit)
        let base = NSColor(color)
        var resolved: NSColor?
        NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            resolved = base.usingColorSpace(.sRGB)
        }
        guard let resolved else { return nil }
        return Resolved(
            hue: Double(resolved.hueComponent) * 360,
            saturation: Double(resolved.saturationComponent),
            brightness: Double(resolved.brightnessComponent)
        )
        #else
        return nil
        #endif
    }

    struct Resolved {
        let hue: Double
        let saturation: Double
        let brightness: Double
    }

    /// The shorter way round the colour wheel, so 350° and 10° are 20° apart
    /// rather than 340°.
    private static func hueSeparation(_ a: Double, _ b: Double) -> Double {
        let difference = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(difference, 360 - difference)
    }

    /// Whether two colours resolve identically in both appearances — how an
    /// entry without a stand-in is recognised, since its `reference` is its
    /// `color`.
    private static func isSameColor(_ a: Color, _ b: Color) -> Bool {
        Appearance.allCases.allSatisfy { appearance in
            guard let left = hueAndSaturation(of: a, in: appearance),
                  let right = hueAndSaturation(of: b, in: appearance)
            else { return false }
            return abs(left.hue - right.hue) < 0.5
                && abs(left.saturation - right.saturation) < 0.01
                && abs(left.brightness - right.brightness) < 0.01
        }
    }
}
