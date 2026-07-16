#if os(macOS)
import SwiftUI

/// The native macOS settings window: toolbar panes with the system's
/// animated resize between them. Content is shared with the iOS settings
/// sheet through the settings row views.
///
/// Grouped forms are vertically greedy, so each pane pins the height its
/// content needs; the window hugs the active pane and animates the change.
struct MacSettingsView: View {
    private enum PaneMetrics {
        static let width: CGFloat = 500
#if canImport(Sparkle)
        static let generalHeight: CGFloat = 460
#else
        static let generalHeight: CGFloat = 355
#endif
        static let appearanceHeight: CGFloat = 560
        static let rulesHeight: CGFloat = 500
        static let aboutHeight: CGFloat = 400
    }

    var body: some View {
        TabView {
            Tab("General", systemImage: "gear") {
                Form {
                    Section("Sound") {
                        SoundSettingsRows()
                    }
                    Section("Gameplay") {
                        GameplaySettingsRows()
                    }
#if canImport(Sparkle)
                    Section("Updates") {
                        UpdatesSettingsRows()
                    }
#endif
                }
                .formStyle(.grouped)
                .frame(width: PaneMetrics.width, height: PaneMetrics.generalHeight)
            }
            Tab("Appearance", systemImage: "paintpalette") {
                Form {
                    Section("Table") {
                        TableSettingsRows()
                    }
                    Section("Cards") {
                        CardsSettingsRows()
                    }
                }
                .formStyle(.grouped)
                .frame(width: PaneMetrics.width, height: PaneMetrics.appearanceHeight)
            }
            Tab("Rules", systemImage: "book") {
                RulesAndScoringView(showsDoneButton: false)
                    .frame(width: PaneMetrics.width, height: PaneMetrics.rulesHeight)
            }
            Tab("About", systemImage: "info.circle") {
                AboutView()
                    .frame(width: PaneMetrics.width, height: PaneMetrics.aboutHeight)
            }
        }
    }
}

#Preview {
    MacSettingsView()
}
#endif
