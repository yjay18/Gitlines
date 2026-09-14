import SwiftUI
import WidgetKit

enum WidtgetPalette {
    static let ink = Color(red: 0.063, green: 0.067, blue: 0.059)
    static let paper = Color(red: 0.937, green: 0.898, blue: 0.804)
    static let orange = Color(red: 0.953, green: 0.357, blue: 0.173)
    static let lime = Color(red: 0.725, green: 0.863, blue: 0.235)
    static let sky = Color(red: 0.412, green: 0.729, blue: 0.859)

    // Compatibility names keep the existing data views and state logic intact.
    static let background = paper
    static let surface = ink
    static let raisedSurface = sky
    static let border = ink.opacity(0.9)
    static let primaryText = ink
    static let secondaryText = ink.opacity(0.62)
    static let green = lime
    static let coral = orange
    static let neutral = ink.opacity(0.18)
}

