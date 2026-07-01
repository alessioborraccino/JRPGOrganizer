import SwiftUI
@preconcurrency import UIKit

enum JRPGTheme {
    static let appBackground = Color(uiColor: uiAppBackground)
    static let navigationBackground = Color(uiColor: uiNavigationBackground)
    static let pinnedControlBackground = adaptive(
        light: ui(0.79, 0.89, 0.99),
        dark: ui(0.09, 0.16, 0.24),
        lightHighContrast: ui(0.73, 0.85, 0.98),
        darkHighContrast: ui(0.12, 0.21, 0.31)
    )
    static let locationHeaderBackground = adaptive(
        light: ui(0.88, 0.94, 1.0),
        dark: ui(0.11, 0.19, 0.28),
        lightHighContrast: ui(0.82, 0.91, 1.0),
        darkHighContrast: ui(0.14, 0.24, 0.35)
    )
    static let accent = Color(uiColor: uiAccent)
    static let accentFill = adaptive(
        light: ui(0.06, 0.32, 0.70),
        dark: ui(0.10, 0.36, 0.76),
        lightHighContrast: ui(0.00, 0.24, 0.58),
        darkHighContrast: ui(0.08, 0.31, 0.70)
    )
    static let onAccent = Color.white
    static let success = adaptive(
        light: ui(0.10, 0.48, 0.22),
        dark: ui(0.45, 0.86, 0.55),
        lightHighContrast: ui(0.03, 0.35, 0.14),
        darkHighContrast: ui(0.61, 0.96, 0.68)
    )
    static let dragonQuestAccent = accent
    static let finalFantasyAccent = adaptive(
        light: ui(0.70, 0.13, 0.24),
        dark: ui(1.0, 0.58, 0.68),
        lightHighContrast: ui(0.53, 0.03, 0.14),
        darkHighContrast: ui(1.0, 0.72, 0.78)
    )
    static let cardBackground = adaptive(
        light: ui(0.985, 0.985, 0.965),
        dark: ui(0.09, 0.13, 0.18),
        lightHighContrast: ui(1.0, 1.0, 0.985),
        darkHighContrast: ui(0.06, 0.09, 0.13)
    )
    static let recessedBackground = adaptive(
        light: ui(1.0, 1.0, 1.0, alpha: 0.70),
        dark: ui(0.04, 0.07, 0.10, alpha: 0.74),
        lightHighContrast: ui(1.0, 1.0, 1.0, alpha: 0.88),
        darkHighContrast: ui(0.02, 0.04, 0.06, alpha: 0.88)
    )
    static let cardBorder = adaptive(
        light: ui(0.0, 0.0, 0.0, alpha: 0.16),
        dark: ui(1.0, 1.0, 1.0, alpha: 0.17),
        lightHighContrast: ui(0.0, 0.0, 0.0, alpha: 0.28),
        darkHighContrast: ui(1.0, 1.0, 1.0, alpha: 0.34)
    )
    static let cardShadow = adaptive(
        light: ui(0.0, 0.0, 0.0, alpha: 0.18),
        dark: ui(0.0, 0.0, 0.0, alpha: 0.50)
    )
    static let primaryText = adaptive(
        light: ui(0.075, 0.082, 0.095),
        dark: ui(0.93, 0.96, 0.99)
    )
    static let secondaryText = adaptive(
        light: ui(0.34, 0.37, 0.41),
        dark: ui(0.70, 0.75, 0.82),
        lightHighContrast: ui(0.22, 0.24, 0.28),
        darkHighContrast: ui(0.82, 0.87, 0.93)
    )
    static let onAppBackground = adaptive(
        light: ui(0.08, 0.13, 0.20),
        dark: ui(0.90, 0.95, 1.0),
        lightHighContrast: ui(0.02, 0.05, 0.09),
        darkHighContrast: ui(1.0, 1.0, 1.0)
    )

    static func modeBackground(for mode: WalkthroughEntryMode) -> Color {
        switch mode {
        case .walkthrough:
            calloutBackground(.important)
        case .completion:
            calloutBackground(.loot)
        case .reference:
            calloutBackground(.reference)
        }
    }

    static func calloutTint(for kind: WalkthroughCalloutKind) -> Color {
        switch kind {
        case .important:
            toneTint(.blue)
        case .tip:
            toneTint(.green)
        case .battle:
            toneTint(.red)
        case .version:
            toneTint(.gray)
        case .warning:
            toneTint(.orange)
        case .loot:
            toneTint(.teal)
        case .enemy:
            toneTint(.purple)
        case .shop:
            toneTint(.indigo)
        case .quest:
            toneTint(.mint)
        case .reference:
            toneTint(.gray)
        case .sourceSpoiler:
            toneTint(.pink)
        case .image:
            toneTint(.cyan)
        case .map:
            toneTint(.brown)
        }
    }

    static func calloutBackground(_ kind: WalkthroughCalloutKind) -> Color {
        switch kind {
        case .important:
            toneBackground(.blue)
        case .tip:
            toneBackground(.green)
        case .battle:
            toneBackground(.red)
        case .version:
            toneBackground(.gray)
        case .warning:
            toneBackground(.orange)
        case .loot:
            toneBackground(.teal)
        case .enemy:
            toneBackground(.purple)
        case .shop:
            toneBackground(.indigo)
        case .quest:
            toneBackground(.mint)
        case .reference:
            toneBackground(.gray)
        case .sourceSpoiler:
            toneBackground(.pink)
        case .image:
            toneBackground(.cyan)
        case .map:
            toneBackground(.brown)
        }
    }

    static func calloutBorder(for kind: WalkthroughCalloutKind) -> Color {
        switch kind {
        case .important:
            toneBorder(.blue)
        case .tip:
            toneBorder(.green)
        case .battle:
            toneBorder(.red)
        case .version:
            toneBorder(.gray)
        case .warning:
            toneBorder(.orange)
        case .loot:
            toneBorder(.teal)
        case .enemy:
            toneBorder(.purple)
        case .shop:
            toneBorder(.indigo)
        case .quest:
            toneBorder(.mint)
        case .reference:
            toneBorder(.gray)
        case .sourceSpoiler:
            toneBorder(.pink)
        case .image:
            toneBorder(.cyan)
        case .map:
            toneBorder(.brown)
        }
    }

    private static let uiAppBackground = adaptiveUIColor(
        light: ui(0.43, 0.61, 0.78),
        dark: ui(0.035, 0.075, 0.12),
        lightHighContrast: ui(0.35, 0.54, 0.73),
        darkHighContrast: ui(0.015, 0.035, 0.065)
    )
    fileprivate static let uiNavigationBackground = adaptiveUIColor(
        light: ui(0.86, 0.93, 1.0),
        dark: ui(0.07, 0.12, 0.18),
        lightHighContrast: ui(0.80, 0.90, 1.0),
        darkHighContrast: ui(0.04, 0.08, 0.13)
    )
    fileprivate static let uiAccent = adaptiveUIColor(
        light: ui(0.06, 0.34, 0.74),
        dark: ui(0.46, 0.75, 1.0),
        lightHighContrast: ui(0.00, 0.24, 0.58),
        darkHighContrast: ui(0.66, 0.86, 1.0)
    )

    private enum Tone {
        case blue
        case green
        case red
        case gray
        case orange
        case teal
        case purple
        case indigo
        case mint
        case pink
        case cyan
        case brown
    }

    private static func toneTint(_ tone: Tone) -> Color {
        switch tone {
        case .blue:
            adaptive(light: ui(0.04, 0.39, 0.81), dark: ui(0.52, 0.78, 1.0))
        case .green:
            adaptive(light: ui(0.08, 0.48, 0.22), dark: ui(0.49, 0.89, 0.58))
        case .red:
            adaptive(light: ui(0.70, 0.15, 0.12), dark: ui(1.0, 0.70, 0.67))
        case .gray:
            adaptive(light: ui(0.35, 0.39, 0.44), dark: ui(0.76, 0.81, 0.86))
        case .orange:
            adaptive(light: ui(0.64, 0.35, 0.00), dark: ui(1.0, 0.75, 0.42))
        case .teal:
            adaptive(light: ui(0.00, 0.48, 0.46), dark: ui(0.46, 0.86, 0.84))
        case .purple:
            adaptive(light: ui(0.42, 0.24, 0.73), dark: ui(0.78, 0.70, 1.0))
        case .indigo:
            adaptive(light: ui(0.26, 0.32, 0.72), dark: ui(0.72, 0.77, 1.0))
        case .mint:
            adaptive(light: ui(0.08, 0.48, 0.29), dark: ui(0.54, 0.89, 0.70))
        case .pink:
            adaptive(light: ui(0.71, 0.17, 0.45), dark: ui(1.0, 0.69, 0.82))
        case .cyan:
            adaptive(light: ui(0.03, 0.44, 0.54), dark: ui(0.51, 0.87, 0.95))
        case .brown:
            adaptive(light: ui(0.54, 0.35, 0.13), dark: ui(0.91, 0.75, 0.51))
        }
    }

    private static func toneBackground(_ tone: Tone) -> Color {
        switch tone {
        case .blue:
            adaptive(light: ui(0.92, 0.96, 1.0), dark: ui(0.06, 0.15, 0.25))
        case .green:
            adaptive(light: ui(0.91, 0.97, 0.93), dark: ui(0.07, 0.19, 0.12))
        case .red:
            adaptive(light: ui(0.99, 0.93, 0.92), dark: ui(0.23, 0.10, 0.10))
        case .gray:
            adaptive(light: ui(0.94, 0.95, 0.96), dark: ui(0.14, 0.17, 0.20))
        case .orange:
            adaptive(light: ui(1.0, 0.95, 0.88), dark: ui(0.22, 0.14, 0.06))
        case .teal:
            adaptive(light: ui(0.90, 0.97, 0.96), dark: ui(0.06, 0.18, 0.18))
        case .purple:
            adaptive(light: ui(0.95, 0.92, 1.0), dark: ui(0.17, 0.12, 0.25))
        case .indigo:
            adaptive(light: ui(0.93, 0.94, 1.0), dark: ui(0.12, 0.15, 0.26))
        case .mint:
            adaptive(light: ui(0.91, 0.97, 0.94), dark: ui(0.07, 0.19, 0.14))
        case .pink:
            adaptive(light: ui(0.99, 0.93, 0.96), dark: ui(0.24, 0.10, 0.17))
        case .cyan:
            adaptive(light: ui(0.91, 0.97, 0.99), dark: ui(0.06, 0.18, 0.22))
        case .brown:
            adaptive(light: ui(0.97, 0.94, 0.90), dark: ui(0.20, 0.14, 0.08))
        }
    }

    private static func toneBorder(_ tone: Tone) -> Color {
        switch tone {
        case .blue:
            adaptive(light: ui(0.37, 0.62, 0.90), dark: ui(0.33, 0.57, 0.86))
        case .green:
            adaptive(light: ui(0.39, 0.70, 0.48), dark: ui(0.33, 0.64, 0.42))
        case .red:
            adaptive(light: ui(0.84, 0.43, 0.38), dark: ui(0.78, 0.37, 0.34))
        case .gray:
            adaptive(light: ui(0.68, 0.72, 0.77), dark: ui(0.48, 0.55, 0.62))
        case .orange:
            adaptive(light: ui(0.86, 0.58, 0.23), dark: ui(0.78, 0.48, 0.16))
        case .teal:
            adaptive(light: ui(0.30, 0.68, 0.66), dark: ui(0.27, 0.61, 0.60))
        case .purple:
            adaptive(light: ui(0.58, 0.45, 0.85), dark: ui(0.52, 0.41, 0.82))
        case .indigo:
            adaptive(light: ui(0.47, 0.55, 0.88), dark: ui(0.43, 0.50, 0.82))
        case .mint:
            adaptive(light: ui(0.36, 0.70, 0.52), dark: ui(0.32, 0.64, 0.48))
        case .pink:
            adaptive(light: ui(0.85, 0.43, 0.64), dark: ui(0.79, 0.37, 0.58))
        case .cyan:
            adaptive(light: ui(0.34, 0.69, 0.78), dark: ui(0.30, 0.61, 0.70))
        case .brown:
            adaptive(light: ui(0.72, 0.55, 0.34), dark: ui(0.65, 0.47, 0.27))
        }
    }

    private static func adaptive(
        light: UIColor,
        dark: UIColor,
        lightHighContrast: UIColor? = nil,
        darkHighContrast: UIColor? = nil
    ) -> Color {
        Color(uiColor: adaptiveUIColor(
            light: light,
            dark: dark,
            lightHighContrast: lightHighContrast,
            darkHighContrast: darkHighContrast
        ))
    }

    private static func adaptiveUIColor(
        light: UIColor,
        dark: UIColor,
        lightHighContrast: UIColor? = nil,
        darkHighContrast: UIColor? = nil
    ) -> UIColor {
        UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return traits.accessibilityContrast == .high ? darkHighContrast ?? dark : dark
            }

            return traits.accessibilityContrast == .high ? lightHighContrast ?? light : light
        }
    }

    private static func ui(
        _ red: CGFloat,
        _ green: CGFloat,
        _ blue: CGFloat,
        alpha: CGFloat = 1
    ) -> UIColor {
        UIColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

public enum JRPGNavigationAppearance {
    @MainActor
    public static func install() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = JRPGTheme.uiNavigationBackground
        appearance.shadowColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.12)
                : UIColor.black.withAlphaComponent(0.12)
        }
        appearance.titleTextAttributes = [.foregroundColor: UIColor.label]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.label]

        let navigationBar = UINavigationBar.appearance()
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
        navigationBar.compactScrollEdgeAppearance = appearance
        navigationBar.tintColor = JRPGTheme.uiAccent
    }
}

extension View {
    func cardSurface(cornerRadius: CGFloat = 10) -> some View {
        padding()
            .background(JRPGTheme.cardBackground, in: .rect(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(JRPGTheme.cardBorder, lineWidth: 1)
            }
    }
}
