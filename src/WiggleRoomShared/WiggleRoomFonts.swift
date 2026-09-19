//
//  WiggleRoomFonts.swift
//  WiggleRoomShared
//

import SwiftUI
import CoreText

/// Typography for Wiggle Room: **Fraunces** (a variable serif with a real
/// "WONK" axis — literally wonky, characterful letterforms) for headlines,
/// status words, and moments that should feel hand-picked rather than
/// system-default; **SF Rounded with tabular figures** for every number a
/// user reads as data (balances, targets, differences) — the spec is
/// explicit that digits must align as they change (§3.3), which a display
/// serif's proportional figures can't reliably guarantee across weights.
/// Splitting the two keeps the personality without ever risking the numbers
/// — the one thing on every screen that has to stay legible and precise.
enum WiggleRoomFont {

    /// Registers the bundled Fraunces variable fonts with Core Text. Safe to
    /// call more than once (idempotent) and from any target — the main app,
    /// widget extension, and watch app each need their own registration
    /// since they don't share a process.
    static func registerIfNeeded() {
        guard !hasRegistered else { return }
        hasRegistered = true
        for resource in ["Fraunces", "Fraunces-Italic", "Nunito"] {
            guard let url = Bundle.wiggleRoomShared.url(forResource: resource, withExtension: "ttf") else {
                continue
            }
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        }
    }

    private static var hasRegistered = false

    /// A Fraunces instance at a specific point on its variable axes.
    /// - `weight`: 100 (Thin) ... 900 (Black).
    /// - `opticalSize`: 9 (text-like, sturdy) ... 144 (display, high-contrast,
    ///   almost hand-lettered) — defaults to tracking the point size, which
    ///   is what a "real" optical-size axis is for.
    /// - `wonky`: 0 (conventional serif shapes) ... 1 (Fraunces' signature
    ///   wonky alternates) — defaults on, since a *little* wonk is the whole
    ///   point of this font for this app.
    static func fraunces(
        size: CGFloat,
        weight: CGFloat = 600,
        opticalSize: CGFloat? = nil,
        wonky: CGFloat = 1,
        soft: CGFloat = 0,
        italic: Bool = false
    ) -> Font {
        registerIfNeeded()
        let baseName = italic ? "Fraunces-Italic" : "Fraunces"
        let opsz = min(max(opticalSize ?? size, 9), 144)
        let variations: [Int: CGFloat] = [
            axisTag("wght"): min(max(weight, 100), 900),
            axisTag("opsz"): opsz,
            axisTag("SOFT"): min(max(soft, 0), 100),
            axisTag("WONK"): min(max(wonky, 0), 1),
        ]
        let attributes: [CFString: Any] = [
            kCTFontNameAttribute: baseName,
            kCTFontVariationAttribute: variations,
        ]
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        let ctFont = CTFontCreateWithFontDescriptor(descriptor, size, nil)
        return Font(ctFont)
    }

    /// A display headline moment — nav titles, big section headers, the
    /// empty-state title. High optical size for real editorial contrast.
    static func headline(_ size: CGFloat, weight: CGFloat = 700) -> Font {
        fraunces(size: size, weight: weight, opticalSize: size * 1.6, wonky: 1)
    }

    /// The status word above the rings ("Under Budget", "Needs Attention")
    /// — bold, wonky, a little louder than a normal headline.
    static func statusWord(_ size: CGFloat) -> Font {
        fraunces(size: size, weight: 850, opticalSize: size * 1.4, wonky: 1)
    }

    /// The small serif label that names a card or figure ("Current
    /// Balance", "Current Budget") — Fraunces names things; Nunito carries
    /// the figures and captions beneath it.
    static var cardLabel: Font {
        fraunces(size: 13, weight: 600, opticalSize: 24, wonky: 1, soft: 70)
    }

    /// A quieter editorial accent — italic, softened, used sparingly for
    /// captions that should feel like a handwritten aside (e.g. empty
    /// states) rather than system chrome.
    static func aside(_ size: CGFloat) -> Font {
        fraunces(size: size, weight: 500, opticalSize: size, wonky: 0.6, soft: 40, italic: true)
    }

    private static func axisTag(_ tag: String) -> Int {
        var value: UInt32 = 0
        for scalar in tag.unicodeScalars { value = (value << 8) + scalar.value }
        return Int(value)
    }

    #if os(iOS)
    /// The `UIFont` equivalent of `headline(_:weight:)`, for the handful of
    /// places styling has to go through `UIFont` rather than SwiftUI's
    /// `Font` — namely `UINavigationBarAppearance`, which SwiftUI has no
    /// native hook for. Built via `UIFontDescriptor`'s raw variation-axis
    /// attribute rather than Core Text, since that's what `UIFont` actually
    /// consumes.
    static func frauncesUIFont(size: CGFloat, weight: CGFloat = 700, opticalSize: CGFloat? = nil, wonky: CGFloat = 1) -> UIFont {
        registerIfNeeded()
        let opsz = min(max(opticalSize ?? size, 9), 144)
        let variationKey = UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)
        let variations: [Int: CGFloat] = [
            axisTag("wght"): min(max(weight, 100), 900),
            axisTag("opsz"): opsz,
            axisTag("WONK"): min(max(wonky, 0), 1),
        ]
        let descriptor = UIFontDescriptor(fontAttributes: [
            .name: "Fraunces",
            variationKey: variations,
        ])
        return UIFont(descriptor: descriptor, size: size)
    }

    /// Applies Fraunces to every navigation bar's large and inline titles,
    /// app-wide — the one styling surface SwiftUI's `Font` can't reach
    /// (`.navigationTitle` always renders through `UINavigationBar`'s own
    /// appearance proxy). Call once at app launch (iOS only per this pass's
    /// scope — see progress notes).
    static func installNavigationBarAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.largeTitleTextAttributes = [.font: frauncesUIFont(size: 34, weight: 700, opticalSize: 48)]
        appearance.titleTextAttributes = [.font: frauncesUIFont(size: 17, weight: 700, opticalSize: 20)]
        let variationKey = UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String)
        let barButtonDescriptor = UIFontDescriptor(fontAttributes: [
            .name: "Nunito",
            variationKey: [axisTag("wght"): CGFloat(700)],
        ])
        let barButtonAttributes: [NSAttributedString.Key: Any] = [.font: UIFont(descriptor: barButtonDescriptor, size: 17)]
        appearance.buttonAppearance.normal.titleTextAttributes = barButtonAttributes
        appearance.doneButtonAppearance.normal.titleTextAttributes = barButtonAttributes
        appearance.backButtonAppearance.normal.titleTextAttributes = barButtonAttributes
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance

        // Assigning a custom UINavigationBarAppearance object resets bar
        // button items to the default label color instead of inheriting the
        // app's global tint — set it explicitly so Cancel/Save/toolbar
        // buttons read as brand-tinted rather than plain black.
        let brandUIColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.62, green: 0.56, blue: 0.98, alpha: 1)
                : UIColor(red: 0.35, green: 0.29, blue: 0.74, alpha: 1)
        }
        UINavigationBar.appearance().tintColor = brandUIColor
        UIView.appearance(whenContainedInInstancesOf: [UINavigationBar.self]).tintColor = brandUIColor
    }
    #endif
}

extension Font {
    /// The body/UI face for everything that isn't a name or headline:
    /// captions, buttons, form fields, tabs, chart labels. **Nunito**
    /// (bundled variable font), scaled with Dynamic Type exactly like the
    /// system text style it replaces. Fraunces (`WiggleRoomFont`) names
    /// things; Nunito carries the rest — see the design direction in the
    /// build spec §3.3.
    static func wiggleText(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        WiggleRoomFont.registerIfNeeded()
        return .custom("Nunito", size: style.wiggleBaseSize, relativeTo: style).weight(weight)
    }

    /// The one font every number in this app should use. Nunito's digits
    /// are natively equal-width (tabular) at every weight, so figures still
    /// align as they change (§3.3) while sharing the app's friendly voice.
    static func wiggleNumber(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        wiggleText(style, weight: weight).monospacedDigit()
    }

    static func wiggleNumber(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        WiggleRoomFont.registerIfNeeded()
        return .custom("Nunito", fixedSize: size).weight(weight).monospacedDigit()
    }

    /// A fixed-size Nunito, for the few places that used `.system(size:)`.
    static func wiggleText(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        WiggleRoomFont.registerIfNeeded()
        return .custom("Nunito", fixedSize: size).weight(weight)
    }
}

extension Font.TextStyle {
    /// The default point size Apple's own text style resolves to at the
    /// standard Dynamic Type setting, so Nunito reads at the same scale.
    fileprivate var wiggleBaseSize: CGFloat {
        switch self {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline: 17
        case .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        default: 17
        }
    }
}

private final class BundleMarker {}

extension Bundle {
    /// The bundle the font files ship in. `WiggleRoomShared` is compiled
    /// directly into each target rather than as its own framework (see
    /// progress notes §"Architecture: WiggleRoomShared"), so its resources
    /// land in *that target's* bundle — `Bundle(for:)` on a type defined
    /// here always resolves to the right one no matter which target is
    /// asking.
    static var wiggleRoomShared: Bundle { Bundle(for: BundleMarker.self) }
}
