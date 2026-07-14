import SwiftUI

#if os(macOS)
struct GameMenuActions {
    var switchVariant: (GameVariant) -> Void
    var newGame: () -> Void
    var redeal: () -> Void
    var undo: () -> Void
    var autoFinish: () -> Void
    var hint: () -> Void
    var showStatistics: () -> Void
}

struct GameMenuState {
    var currentVariant: GameVariant
    var canUndo: Bool
    var canRedeal: Bool
    var canAutoFinish: Bool
    var canHint: Bool
    var isHintVisible: Bool
    var isAutoFinishing: Bool
}

private struct GameMenuActionsFocusedKey: FocusedValueKey {
    typealias Value = GameMenuActions
}

private struct GameMenuStateFocusedKey: FocusedValueKey {
    typealias Value = GameMenuState
}

extension FocusedValues {
    var gameMenuActions: GameMenuActions? {
        get { self[GameMenuActionsFocusedKey.self] }
        set { self[GameMenuActionsFocusedKey.self] = newValue }
    }

    var gameMenuState: GameMenuState? {
        get { self[GameMenuStateFocusedKey.self] }
        set { self[GameMenuStateFocusedKey.self] = newValue }
    }
}

struct GameMenuCommands: Commands {
    @FocusedValue(\.gameMenuActions) private var actions
    @FocusedValue(\.gameMenuState) private var state

    var body: some Commands {
        CommandMenu("Game") {
            Picker("Game Mode", selection: Binding(
                get: { state?.currentVariant ?? .klondike },
                set: { actions?.switchVariant($0) }
            )) {
                ForEach(Array(GameVariant.allCases.enumerated()), id: \.element) { index, variant in
                    if let shortcut = Self.variantShortcut(at: index) {
                        Text(variant.title)
                            .keyboardShortcut(shortcut, modifiers: .command)
                            .tag(variant)
                    } else {
                        Text(variant.title)
                            .tag(variant)
                    }
                }
            }
            .pickerStyle(.inline)
            .disabled(actions == nil)

            Divider()

            Button {
                actions?.newGame()
            } label: {
                Label("New Game", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(actions == nil)

            Button {
                actions?.redeal()
            } label: {
                Label("Redeal", systemImage: "arrow.clockwise")
            }
            .disabled(!(state?.canRedeal ?? false))

            Divider()

            Button {
                actions?.undo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward")
            }
            .keyboardShortcut("z", modifiers: [.command, .option])
            .disabled(!(state?.canUndo ?? false))

            Button {
                actions?.autoFinish()
            } label: {
                Label(state?.isAutoFinishing == true ? "Stop Auto Finish" : "Auto Finish", systemImage: "bolt")
            }
            .disabled(!(state?.canAutoFinish ?? false))

            if state?.isHintVisible ?? false {
                Button {
                    actions?.hint()
                } label: {
                    Label("Hint", systemImage: "lightbulb")
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .disabled(!(state?.canHint ?? false))
            }

            Divider()

            Button {
                actions?.showStatistics()
            } label: {
                Label("Statistics…", systemImage: "chart.bar")
            }
            .disabled(actions == nil)
        }
    }

    /// ⌘0 through ⌘9 select the first ten variants in presentation order;
    /// any beyond that get no shortcut — there are only ten digit keys.
    private static func variantShortcut(at index: Int) -> KeyEquivalent? {
        guard (0...9).contains(index) else { return nil }
        return KeyEquivalent(Character("\(index)"))
    }
}
#endif
