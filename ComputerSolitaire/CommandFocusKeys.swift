import SwiftUI

private struct ShowSettingsKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

private struct ShowRulesAndScoringKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

extension FocusedValues {
    var showSettingsCommand: Binding<Bool>? {
        get { self[ShowSettingsKey.self] }
        set { self[ShowSettingsKey.self] = newValue }
    }

    var showRulesAndScoringCommand: Binding<Bool>? {
        get { self[ShowRulesAndScoringKey.self] }
        set { self[ShowRulesAndScoringKey.self] = newValue }
    }
}
