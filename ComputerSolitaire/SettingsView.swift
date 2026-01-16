import SwiftUI

enum DrawMode: Int, CaseIterable {
    case one = 1
    case three = 3

    var title: String {
        switch self {
        case .one:
            return "1-card"
        case .three:
            return "3-card"
        }
    }
}

enum SettingsKey {
    static let cardTiltEnabled = "settings.cardTiltEnabled"
    static let drawMode = "settings.drawMode"
}

extension Notification.Name {
    static let openSettings = Notification.Name("openSettings")
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.cardTiltEnabled) private var isCardTiltEnabled = true
    @AppStorage(SettingsKey.drawMode) private var drawModeRawValue = DrawMode.three.rawValue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                SettingsCard(title: "Cards") {
                    Toggle(isOn: $isCardTiltEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Natural card tilt")
                                .font(.subheadline.weight(.semibold))
                            Text("Adds a subtle organic angle to each card.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }

                SettingsCard(title: "Draw Mode") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Stock draw")
                            .font(.subheadline.weight(.semibold))
                        Picker("Stock draw", selection: $drawModeRawValue) {
                            ForEach(DrawMode.allCases, id: \.rawValue) { mode in
                                Text(mode.title).tag(mode.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .disabled(true)
                        Text("1-card draw is coming soon.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .onAppear {
                        drawModeRawValue = DrawMode.three.rawValue
                    }
                }
            }
            .padding(24)
        }
        .frame(minWidth: 420, idealWidth: 480, maxWidth: 520, minHeight: 260)
    }

    private var header: some View {
        HStack {
            Text("Settings")
                .font(.title2.weight(.semibold))
            Spacer()
            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(.bottom, 4)
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

#Preview {
    SettingsView()
}
