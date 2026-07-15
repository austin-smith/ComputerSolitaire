import SwiftUI

/// The player's gameplay animation pace, from the Animation Speed setting.
/// `scale` multiplies every gameplay animation duration — moves, flights,
/// draws, deals, undo, flips — so the whole board keeps one rhythm.
struct AnimationSpeed: Identifiable, Equatable {
    let id: String
    let title: String
    /// Multiplies gameplay animation durations; 0 means no motion at all.
    let scale: Double

    static let normal = AnimationSpeed(id: "normal", title: "Normal", scale: 1)
    static let fast = AnimationSpeed(id: "fast", title: "Fast", scale: 0.5)
    static let instant = AnimationSpeed(id: "instant", title: "Instant", scale: 0)

    static let all: [AnimationSpeed] = [normal, fast, instant]
    static let defaultValue: AnimationSpeed = .normal

    static func from(rawValue: String) -> AnimationSpeed {
        all.first { $0.id == rawValue } ?? defaultValue
    }
}

/// One gate for every gameplay animation: the speed setting scales durations,
/// and the system Reduce Motion switch clamps to instant regardless of the
/// setting. Animation builders return `nil` when motion is off, which both
/// `withAnimation(_:)` and `.animation(_:value:)` treat as "apply without
/// animating". Completion scheduling must go through `duration(_:)` with the
/// same base value the builder received, so flights and their cleanup can
/// never drift apart.
///
/// The win celebration is deliberately outside this policy's speed scaling —
/// it is a reward, not a wait — but Reduce Motion suppresses it too (see the
/// `isWin` observer in ContentView).
struct MotionPolicy: Equatable {
    /// 1 normal, 0.5 fast, 0 instant or system Reduce Motion.
    let scale: Double

    init(speed: AnimationSpeed, reduceMotion: Bool) {
        scale = reduceMotion ? 0 : speed.scale
    }

    var isInstant: Bool { scale == 0 }

    /// A flight or completion delay at the current pace.
    func duration(_ base: Double) -> Double {
        base * scale
    }

    func spring(response: Double, dampingFraction: Double) -> Animation? {
        isInstant ? nil : .spring(response: response * scale, dampingFraction: dampingFraction)
    }

    func easeOut(_ baseDuration: Double) -> Animation? {
        isInstant ? nil : .easeOut(duration: baseDuration * scale)
    }

    func easeInOut(_ baseDuration: Double) -> Animation? {
        isInstant ? nil : .easeInOut(duration: baseDuration * scale)
    }
}

private struct MotionPolicyKey: EnvironmentKey {
    static let defaultValue = MotionPolicy(speed: .defaultValue, reduceMotion: false)
}

extension EnvironmentValues {
    var motionPolicy: MotionPolicy {
        get { self[MotionPolicyKey.self] }
        set { self[MotionPolicyKey.self] = newValue }
    }
}
