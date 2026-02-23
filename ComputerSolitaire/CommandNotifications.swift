import Foundation

enum GameCommand {
    case newGame
    case redeal
    case undo
    case autoFinish
    case hint
}

extension Notification.Name {
    static let openSettings = Notification.Name("openSettings")
    static let openRulesAndScoring = Notification.Name("openRulesAndScoring")
    static let openStatistics = Notification.Name("openStatistics")
    static let gameCommand = Notification.Name("gameCommand")
}
