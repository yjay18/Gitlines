import SwiftUI
import WidgetKit

@main
struct WidtgetWidgetBundle: WidgetBundle {
    var body: some Widget {
        WidtgetWidget()
    }
}

// In vibrant (de-emphasized) mode macOS supplies its own material, so a solid
// theme colour here — especially a light one like Broadsheet's paper — washes the
// widget out. Only paint the theme colour in full colour.
private struct WidgetContainerBackground: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let theme: WidgetVisualTheme

    var body: some View {
        renderingMode == .fullColor ? theme.containerBackgroundColor : Color.clear
    }
}

struct WidtgetWidget: Widget {
    static let kind = WidtgetWidgetKind.value

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: Self.kind,
            intent: WidtgetConfigurationIntent.self,
            provider: ActivityProvider()
        ) { entry in
            WidtgetWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetContainerBackground(theme: entry.preferences.visualTheme)
                }
        }
        .configurationDisplayName("Gitlines")
        .description("A focused view of additions, deletions, commits, and repository activity.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
        .contentMarginsDisabled()
    }
}
