import SwiftUI

/// App-wide design tokens: quiet native surfaces, one primary accent, and an 8-pt spacing scale.
enum Theme {
    // Browser-confirmed Apple system green (#30D158 dark / #34C759 light). Was teal #198C91.
    static let accent = Color(uiColor: UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 48/255,  green: 209/255, blue: 88/255, alpha: 1)   // #30D158
            : UIColor(red: 52/255,  green: 199/255, blue: 89/255, alpha: 1)   // #34C759
    })
    /// Ink on the accent (button label): #053314. Mirrors macOS MacPalette.accentInk.
    static let accentInk = Color(red: 5/255, green: 51/255, blue: 20/255)     // #053314
    /// Prosody contour + nuclear stress green. Bright #46D17F in dark; deeper #1F8F4E in light (≥4.5:1 on white).
    static let prosody = Color(uiColor: UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 70/255,  green: 209/255, blue: 127/255, alpha: 1)  // #46D17F
            : UIColor(red: 31/255,  green: 143/255, blue: 78/255,  alpha: 1)  // #1F8F4E
    })
    /// Inserted-word highlight in the idiomatic headline. Bright #7BE6A4 in dark; deeper #1F8F4E in light.
    static let inserted = Color(uiColor: UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 123/255, green: 230/255, blue: 164/255, alpha: 1) // #7BE6A4
            : UIColor(red: 31/255,  green: 143/255, blue: 78/255,  alpha: 1)  // #1F8F4E
    })
    /// Deleted-word color for the "你说的" diff line. Bright #FF7A70 in dark; deeper #C7372C in light.
    static let deleted = Color(uiColor: UIColor { tc in
        tc.userInterfaceStyle == .dark
            ? UIColor(red: 255/255, green: 122/255, blue: 112/255, alpha: 1) // #FF7A70
            : UIColor(red: 199/255, green: 55/255,  blue: 44/255,  alpha: 1)  // #C7372C
    })
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let elevatedSurface = Color(uiColor: .systemBackground)
    static let separator = Color.primary.opacity(0.08)

    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 20
        static let xl: CGFloat = 28
    }

    static let radius: CGFloat = 8
    static let controlRadius: CGFloat = 10
}

/// Low-contrast native grouping surface. Use sparingly for real hierarchy.
struct CardBackground: ViewModifier {
    var padding: CGFloat = Theme.Space.l
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(Theme.elevatedSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(Theme.separator, lineWidth: 0.5)
            )
    }
}

extension View {
    func card(padding: CGFloat = Theme.Space.l) -> some View {
        modifier(CardBackground(padding: padding))
    }
}

/// Prominent primary action with a pressed state.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .fill(Theme.accent.opacity(configuration.isPressed ? 0.82 : 1))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
