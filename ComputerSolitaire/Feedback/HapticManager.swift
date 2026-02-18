import Observation
import SwiftUI

@MainActor
@Observable
final class HapticManager {
    static let shared = HapticManager()

    enum Event {
        case cardPickUp
        case stockDraw
        case wasteRecycle
        case cardFlipFaceUp
        case invalidDrop
        case undoMove
        case settingsSelection
    }

    private(set) var trigger: UInt64 = 0
    private var lastEvent: Event?

    private init() {}

    func play(_ event: Event) {
#if os(iOS)
        lastEvent = event
        trigger &+= 1
#endif
    }

    var feedbackForTrigger: SensoryFeedback? {
#if os(iOS)
        guard let lastEvent else { return nil }
        return lastEvent.sensoryFeedback
#else
        return nil
#endif
    }
}

private extension HapticManager.Event {
    var sensoryFeedback: SensoryFeedback {
        switch self {
        case .cardPickUp:
            return .impact
        case .stockDraw:
            return .impact
        case .wasteRecycle:
            return .impact
        case .cardFlipFaceUp, .undoMove:
            return .selection
        case .invalidDrop:
            return .error
        case .settingsSelection:
            return .impact
        }
    }
}
