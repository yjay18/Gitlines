import SwiftUI

// All dashboard surfaces share the selected theme, including repository details.
struct ThemePalette {
    let ink: Color      // page background
    let panel: Color    // card surface
    let lifted: Color   // raised surface / pill
    let line: Color     // hairline
    let text: Color     // primary text
    let muted: Color    // secondary text
    let green: Color    // additions / positive
    let coral: Color    // deletions / negative

    var fontDesign: Font.Design = .rounded
    var cornerRadius: CGFloat = 16

    static let dark = ThemePalette(
        ink: DashboardPalette.ink, panel: DashboardPalette.panel, lifted: DashboardPalette.lifted,
        line: DashboardPalette.line, text: DashboardPalette.text, muted: DashboardPalette.muted,
        green: DashboardPalette.green, coral: DashboardPalette.coral)
}

extension WidgetVisualTheme {
    var dashboardPalette: ThemePalette {
        switch self {
        case .defaultTheme:
            .dark
        case .blockwork:
            ThemePalette(
                ink: Color(red: 0.88, green: 0.82, blue: 0.69),
                panel: Color(red: 0.937, green: 0.898, blue: 0.804),
                lifted: Color(red: 0.76, green: 0.81, blue: 0.52),
                line: Color(red: 0.063, green: 0.067, blue: 0.059),
                text: Color(red: 0.063, green: 0.067, blue: 0.059),
                muted: Color(red: 0.35, green: 0.32, blue: 0.26),
                green: Color(red: 0.18, green: 0.36, blue: 0.12),
                coral: Color(red: 0.74, green: 0.24, blue: 0.08),
                fontDesign: .monospaced, cornerRadius: 0)
        case .glasshouse:
            ThemePalette(
                ink: Color(red: 0.110, green: 0.114, blue: 0.129),
                panel: Color.white.opacity(0.06), lifted: Color.white.opacity(0.10),
                line: Color.white.opacity(0.12),
                text: Color(red: 0.949, green: 0.953, blue: 0.961), muted: Color.white.opacity(0.5),
                green: Color(red: 0.494, green: 0.886, blue: 0.659),
                coral: Color(red: 0.941, green: 0.525, blue: 0.549),
                fontDesign: .default, cornerRadius: 12)
        case .phosphor:
            ThemePalette(
                ink: Color(red: 0.024, green: 0.035, blue: 0.039),
                panel: Color.white.opacity(0.04), lifted: Color(red: 0.055, green: 0.14, blue: 0.09),
                line: Color(red: 0.290, green: 0.941, blue: 0.541).opacity(0.18),
                text: Color(red: 0.290, green: 0.941, blue: 0.541),
                muted: Color(red: 0.38, green: 0.68, blue: 0.46),
                green: Color(red: 0.290, green: 0.941, blue: 0.541),
                coral: Color(red: 1.0, green: 0.702, blue: 0.251),
                fontDesign: .monospaced, cornerRadius: 2)
        case .broadsheet:
            ThemePalette(
                ink: Color(red: 0.914, green: 0.894, blue: 0.835),
                panel: Color(red: 0.098, green: 0.090, blue: 0.059).opacity(0.05),
                lifted: Color(red: 0.098, green: 0.090, blue: 0.059).opacity(0.09),
                line: Color(red: 0.098, green: 0.090, blue: 0.059).opacity(0.15),
                text: Color(red: 0.098, green: 0.090, blue: 0.059),
                muted: Color(red: 0.427, green: 0.396, blue: 0.333),
                green: Color(red: 0.098, green: 0.090, blue: 0.059),
                coral: Color(red: 0.620, green: 0.184, blue: 0.106),
                fontDesign: .serif, cornerRadius: 0)
        case .arcade:
            ThemePalette(
                ink: Color(red: 0.059, green: 0.220, blue: 0.059),
                panel: Color(red: 0.114, green: 0.302, blue: 0.114).opacity(0.55),
                lifted: Color(red: 0.114, green: 0.302, blue: 0.114),
                line: Color(red: 0.188, green: 0.384, blue: 0.188),
                text: Color(red: 0.545, green: 0.675, blue: 0.059),
                muted: Color(red: 0.64, green: 0.74, blue: 0.40),
                green: Color(red: 0.608, green: 0.737, blue: 0.059),
                coral: Color(red: 0.851, green: 0.310, blue: 0.118),
                fontDesign: .monospaced, cornerRadius: 0)
        }
    }
}

private struct ThemePaletteKey: EnvironmentKey {
    static let defaultValue: ThemePalette = .dark
}

extension EnvironmentValues {
    var themePalette: ThemePalette {
        get { self[ThemePaletteKey.self] }
        set { self[ThemePaletteKey.self] = newValue }
    }
}
