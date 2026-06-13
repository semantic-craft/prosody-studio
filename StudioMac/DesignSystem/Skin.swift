import SwiftUI
import AppKit

/// School-named **Skin** = a switchable colour world (surfaces / ink / accent + derived),
/// ported 1:1 from the Claude Design handoff (`docs/onboarding/claude-design-handoff/`).
///
/// Layout / spacing / type scale / radii / density are **fixed** across skins (see
/// `SkinMetrics`); only the colour world changes. Each token auto-adapts light/dark via an
/// `NSColor` dynamic provider, so the *skin* is the runtime choice and light/dark stays
/// system-driven. Default = **深大红** (`.shenda`); v1 also ships **斯坦福** (`.stanford`).
///
/// Scope: the macOS **app-wide** colour system. `MacPalette` and `SettingsTheme` resolve their
/// brand accent (and matching surfaces) from `Skin.current`, so the chosen skin tints the whole
/// app — the former Apple-green accent is gone. iOS `Theme` is out of scope (macOS-only for now).
/// See `docs/adr/0026-skin-system-school-palettes.md`.
enum Skin: String, CaseIterable, Identifiable, Sendable {
    case shenda
    case stanford
    case wuda
    case xiada

    var id: String { rawValue }

    /// Persisted choice; first-run default.
    static let `default`: Skin = .shenda
    static let defaultsKey = "appearance.skin"

    /// The active skin resolved from the persisted choice — the value-layer source of truth the
    /// app-wide palettes (`MacPalette`, `SettingsTheme`) read so a skin choice tints the whole
    /// app, not just onboarding. `AppearanceStore` is the reactive (view-observing) holder over
    /// the same key; this getter is non-isolated for use from static colour tokens. (Static
    /// reads resolve at render time, so a *live* in-app skin swap re-tints onboarding immediately
    /// — it observes `AppearanceStore` — and the rest of the app on its next render / relaunch.)
    static var current: Skin {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(Skin.init(rawValue:)) ?? .default
    }

    var displayName: String {
        switch self {
        case .shenda:   "深大红"
        case .stanford: "斯坦福"
        case .wuda:     "武大绿"
        case .xiada:    "厦大蓝"
        }
    }

    /// One-line tagline shown on the step-1 skin card.
    var tagline: String {
        switch self {
        case .shenda:   "暖纸 + 品红 · 默认"
        case .stanford: "冷灰 + Cardinal"
        case .wuda:     "素纸 + 珞珈青"
        case .xiada:    "海韵白 + 嘉庚蓝"
        }
    }

    var palette: SkinPalette {
        switch self {
        case .shenda:   Self.shenda_
        case .stanford: Self.stanford_
        case .wuda:     Self.wuda_
        case .xiada:    Self.xiada_
        }
    }

    // MARK: - Palettes (light / dark per token, from the handoff token block)

    private static let shenda_ = SkinPalette(
        accent:      dyn(0xA82C53, 0xE06A8E),
        accentDeep:  dyn(0x8E2447, 0xC24E72),
        accentSoft:  dyn(0x9D7C7C, 0x8D6C6C),
        onAccent:    dyn(0xFBF9F5, 0x1A1816),
        bg:          dyn(0xEDE8E0, 0x1A1816),
        sidebar:     dyn(0xE6E0D6, 0x211E1B),
        card:        dyn(0xFBF9F5, 0x262321),
        card2:       dyn(0xF3EFE7, 0x211E1C),
        field:       dyn(0xFFFFFF, 0x16140F),
        ink:         dyn(0x2A2622, 0xECE4D8),
        ink2:        dyn(0x6B6A64, 0xA89E90),
        ink3:        dyn(0x9A9387, 0x766D62),
        hair:        dyn(0x2A2622, 0xECE4D8, lightA: 0.10, darkA: 0.10),
        hairStrong:  dyn(0x2A2622, 0xECE4D8, lightA: 0.17, darkA: 0.16),
        paperGrain:  dyn(0x785A3C, 0xFFEBCD, lightA: 0.04, darkA: 0.025)
    )

    private static let stanford_ = SkinPalette(
        accent:      dyn(0x8C1515, 0xB83A4B),
        accentDeep:  dyn(0x820000, 0x8C1515),
        accentSoft:  dyn(0x8A7375, 0x7D646C),
        onAccent:    dyn(0xFBFBFC, 0xF2F2F0),
        bg:          dyn(0xE9EAEC, 0x1B1C1E),
        sidebar:     dyn(0xE1E3E6, 0x212327),
        card:        dyn(0xFBFBFC, 0x26282C),
        card2:       dyn(0xF1F2F4, 0x212327),
        field:       dyn(0xFFFFFF, 0x141517),
        ink:         dyn(0x2E2D29, 0xE8EAED),
        ink2:        dyn(0x53565A, 0x9DA1A6),   // Cool Grey
        ink3:        dyn(0x8A8D90, 0x6C7075),
        hair:        dyn(0x2E2D29, 0xE8EAED, lightA: 0.11, darkA: 0.10),
        hairStrong:  dyn(0x2E2D29, 0xE8EAED, lightA: 0.18, darkA: 0.16),
        paperGrain:  dyn(0x3C465A, 0x96AAC8, lightA: 0.035, darkA: 0.03)
    )

    private static let wuda_ = SkinPalette(
        accent:      dyn(0x2A8367, 0x3CA081),
        accentDeep:  dyn(0x1F6B52, 0x2A8367),
        accentSoft:  dyn(0x658A7E, 0x5D8477),
        onAccent:    dyn(0xF9FAF8, 0x121413),
        bg:          dyn(0xEBEEEA, 0x171918),
        sidebar:     dyn(0xE2E6E2, 0x1C1E1D),
        card:        dyn(0xF8FBF9, 0x212423),
        card2:       dyn(0xEFF2EE, 0x1C1E1D),
        field:       dyn(0xFFFFFF, 0x121413),
        ink:         dyn(0x282D2A, 0xE5EAE7),
        ink2:        dyn(0x565F5A, 0x98A19C),
        ink3:        dyn(0x8A938E, 0x66706B),
        hair:        dyn(0x282D2A, 0xE5EAE7, lightA: 0.10, darkA: 0.10),
        hairStrong:  dyn(0x282D2A, 0xE5EAE7, lightA: 0.17, darkA: 0.16),
        paperGrain:  dyn(0x2C463C, 0x86B0A0, lightA: 0.035, darkA: 0.03)
    )

    private static let xiada_ = SkinPalette(
        accent:      dyn(0x1D4A8C, 0x4879C5),
        accentDeep:  dyn(0x123061, 0x1D4A8C),
        accentSoft:  dyn(0x5A7091, 0x4D6991),
        onAccent:    dyn(0xF8FAFC, 0x0F141C),
        bg:          dyn(0xEDF1F5, 0x16181B),
        sidebar:     dyn(0xE4E9EF, 0x1B1E22),
        card:        dyn(0xF8FAFC, 0x212429),
        card2:       dyn(0xEFF2F7, 0x1B1E22),
        field:       dyn(0xFFFFFF, 0x121416),
        ink:         dyn(0x242A36, 0xE6EAF0),
        ink2:        dyn(0x5C6A81, 0x98A4B8),
        ink3:        dyn(0x8898AF, 0x66758A),
        hair:        dyn(0x242A36, 0xE6EAF0, lightA: 0.09, darkA: 0.10),
        hairStrong:  dyn(0x242A36, 0xE6EAF0, lightA: 0.16, darkA: 0.16),
        paperGrain:  dyn(0x2C405A, 0x869AB0, lightA: 0.03, darkA: 0.025)
    )

    // MARK: - Dynamic colour plumbing (shared with SettingsTheme via DynamicColor)

    private static func dyn(_ light: UInt32, _ dark: UInt32,
                            lightA: Double = 1, darkA: Double = 1) -> Color {
        DynamicColor.make(light, dark, lightA: lightA, darkA: darkA)
    }
}

/// One skin's colour world. Base tokens are dynamic (light/dark); accent washes are derived
/// so a skin swap re-tints everything (parity with the handoff's `color-mix(... var(--accent))`).
struct SkinPalette: Sendable {
    let accent: Color
    let accentDeep: Color
    /// `color-mix(accent 22%, ink3)` precomputed (macOS 14 has no `Color.mix`) — defocused accent.
    let accentSoft: Color
    /// Text/glyph colour on top of `accent`.
    let onAccent: Color

    let bg: Color          // window field
    let sidebar: Color     // step rail
    let card: Color        // ivory / paper card
    let card2: Color       // secondary card / group base
    let field: Color       // editable field

    let ink: Color         // primary text
    let ink2: Color        // secondary text
    let ink3: Color        // tertiary / placeholder

    let hair: Color        // hairline
    let hairStrong: Color  // stronger hairline
    let paperGrain: Color  // warm/cool grain texture

    // Derived from accent — `color-mix(in srgb, accent N%, transparent)` == accent.opacity(N).
    var accentWash: Color  { accent.opacity(0.09) }   // selected wash
    var accentWash2: Color { accent.opacity(0.16) }   // heavier wash / focus ring
    var accentLine: Color  { accent.opacity(0.34) }   // callout border
}

/// Fixed, skin-independent design metrics (the handoff's `:root` constants).
enum SkinMetrics {
    // Radii
    static let radiusWindow: CGFloat = 18
    static let radiusCard: CGFloat = 13
    static let radiusSmall: CGFloat = 9

    // Spacing (≈8-pt rhythm)
    static let sp1: CGFloat = 6
    static let sp2: CGFloat = 10
    static let sp3: CGFloat = 16
    static let sp4: CGFloat = 22
    static let sp5: CGFloat = 32
    static let sp6: CGFloat = 44

    // Type scale (px == pt) — the adjudicated 7-level scale (issue 309).
    // Absorption map: 28←28,30 · 24←24,22,20 · 16←16,17 · 15←15,14.5,14 ·
    // 13←13,13.5,12.5 · 12←12,11.5 · 11←11,10.5,10,9. New text uses these
    // tokens, never `.system(size: <literal>)`; icon sizes may stay literal.
    static let fsDisplay: CGFloat = 28
    static let fsTitle: CGFloat = 24
    static let fsCard: CGFloat = 16
    static let fsBody: CGFloat = 15
    static let fsFoot: CGFloat = 13
    static let fsLabel: CGFloat = 12
    static let fsCaption: CGFloat = 11

    /// Editorial serif for titles. The app ships **Charter**; the handoff used Source Serif 4
    /// as the web approximation.
    static func serif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.custom("Charter", size: size).weight(weight)
    }
    static let mono = Font.system(.body, design: .monospaced)

    // MARK: - Component dimensions
    //
    // Named sizes for recurring control anatomy (HeroUI-style component tokens),
    // so fields/tiles/card insets stop being per-call magic numbers. Distinct
    // from the spacing scale (sp1–6) — these are control geometry, not rhythm.

    /// Editable field / key-input height (was an inconsistent 36 vs 32).
    static let fieldHeight: CGFloat = 36
    /// Square icon tile in a capability/section header.
    static let iconTile: CGFloat = 34
    /// Inner padding of a paper card.
    static let cardPadding: CGFloat = 18
}
