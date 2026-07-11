import CoreGraphics
import Foundation

struct WinCascadeCardState: Identifiable {
    let id: UUID
    let card: Card
    let size: CGSize
    var position: CGPoint
    var velocity: CGVector
    var rotationDegrees: Double
    var angularVelocityDegreesPerSecond: Double
    let activationDelay: TimeInterval
    var elapsed: TimeInterval = 0
    var bounceCount: Int = 0
    var isSettled: Bool = false
}

enum WinCascadeCoordinator {
    private struct LaunchCard {
        let pile: Int
        let depth: Int
        let card: Card
    }

    private static let gravity: CGFloat = 1_700
    private static let sideBounceDamping: CGFloat = 0.84
    private static let topBounceDamping: CGFloat = 0.62
    private static let floorBounceDamping: CGFloat = 0.66
    private static let floorHorizontalFriction: CGFloat = 0.93
    private static let floorSettleVerticalSpeed: CGFloat = 115
    private static let angularVelocityDampingOnBounce: Double = 0.82
    private static let maxActiveLifetime: TimeInterval = 6.5
    private static let baseLaunchDelay: TimeInterval = 0.03

    static func makeInitialStates(
        foundations: [[Card]],
        foundationFrames: [Int: CGRect],
        fallbackLaunchFrame: CGRect
    ) -> [WinCascadeCardState] {
        let launchCards = interleavedLaunchCards(from: foundations)
        guard !launchCards.isEmpty else { return [] }

        return launchCards.enumerated().map { sequence, launch in
            let launchFrame = foundationFrames[launch.pile] ?? fallbackLaunchFrame
            let origin = CGPoint(x: launchFrame.midX, y: launchFrame.midY)
            let jitterX = CGFloat.random(in: -(launchFrame.width * 0.12)...(launchFrame.width * 0.12))
            let jitterY = CGFloat.random(in: -(launchFrame.height * 0.08)...(launchFrame.height * 0.08))
            let pileBias = CGFloat(launch.pile - 1) * 30

            var card = launch.card
            card.isFaceUp = true

            return WinCascadeCardState(
                id: launch.card.id,
                card: card,
                size: launchFrame.size,
                position: CGPoint(
                    x: origin.x + jitterX,
                    y: origin.y + jitterY - CGFloat(launch.depth) * 0.6
                ),
                velocity: CGVector(
                    dx: CGFloat.random(in: -240...240) + pileBias,
                    dy: CGFloat.random(in: -760 ... -520)
                ),
                rotationDegrees: Double.random(in: -7...7),
                angularVelocityDegreesPerSecond: Double.random(in: -170...170),
                activationDelay: baseLaunchDelay * Double(sequence)
            )
        }
    }

    static func step(
        states: inout [WinCascadeCardState],
        deltaTime: TimeInterval,
        boardBounds: CGRect
    ) {
        guard !states.isEmpty else { return }
        guard boardBounds.width > 0, boardBounds.height > 0 else { return }

        let timeStep = CGFloat(max(1.0 / 120.0, min(1.0 / 30.0, deltaTime)))

        for index in states.indices {
            states[index].elapsed += TimeInterval(timeStep)
            if states[index].elapsed < states[index].activationDelay {
                continue
            }
            if states[index].isSettled {
                continue
            }

            var item = advanced(states[index], timeStep: timeStep)
            if resolveBoundaryCollisions(for: &item, in: boardBounds) {
                item.bounceCount += 1
                item.angularVelocityDegreesPerSecond *= angularVelocityDampingOnBounce
            }

            states[index] = item
        }

        settleExpiredStates(&states, in: boardBounds)
    }

    private static func advanced(_ state: WinCascadeCardState, timeStep: CGFloat) -> WinCascadeCardState {
        var result = state
        result.velocity.dy += gravity * timeStep
        result.position.x += result.velocity.dx * timeStep
        result.position.y += result.velocity.dy * timeStep
        result.rotationDegrees += result.angularVelocityDegreesPerSecond * Double(timeStep)
        return result
    }

    private static func resolveBoundaryCollisions(
        for item: inout WinCascadeCardState,
        in bounds: CGRect
    ) -> Bool {
        let halfWidth = item.size.width * 0.5
        let halfHeight = item.size.height * 0.5
        var bounced = false
        if item.position.x - halfWidth < bounds.minX {
            item.position.x = bounds.minX + halfWidth
            item.velocity.dx = abs(item.velocity.dx) * sideBounceDamping
            bounced = true
        }
        if item.position.x + halfWidth > bounds.maxX {
            item.position.x = bounds.maxX - halfWidth
            item.velocity.dx = -abs(item.velocity.dx) * sideBounceDamping
            bounced = true
        }
        if item.position.y - halfHeight < bounds.minY {
            item.position.y = bounds.minY + halfHeight
            item.velocity.dy = abs(item.velocity.dy) * topBounceDamping
            bounced = true
        }
        if item.position.y + halfHeight > bounds.maxY {
            resolveFloorCollision(for: &item, floor: bounds.maxY - halfHeight)
            bounced = true
        }
        return bounced
    }

    private static func resolveFloorCollision(for item: inout WinCascadeCardState, floor: CGFloat) {
        item.position.y = floor
        let reboundSpeed = abs(item.velocity.dy) * floorBounceDamping
        if reboundSpeed < floorSettleVerticalSpeed {
            item.velocity = .zero
            item.angularVelocityDegreesPerSecond = 0
            item.isSettled = true
        } else {
            item.velocity.dy = -reboundSpeed
            item.velocity.dx *= floorHorizontalFriction
        }
    }

    private static func settleExpiredStates(
        _ states: inout [WinCascadeCardState],
        in bounds: CGRect
    ) {
        for index in states.indices where !states[index].isSettled {
            let activeAge = max(0, states[index].elapsed - states[index].activationDelay)
            guard activeAge > maxActiveLifetime else { continue }
            states[index].position.y = bounds.maxY - states[index].size.height * 0.5
            states[index].velocity = .zero
            states[index].angularVelocityDegreesPerSecond = 0
            states[index].isSettled = true
        }
    }

    static func makeCompletedStates(
        foundations: [[Card]],
        foundationFrames: [Int: CGRect],
        fallbackLaunchFrame: CGRect,
        boardBounds: CGRect
    ) -> [WinCascadeCardState] {
        guard boardBounds.width > 0, boardBounds.height > 0 else { return [] }
        var states = makeInitialStates(
            foundations: foundations,
            foundationFrames: foundationFrames,
            fallbackLaunchFrame: fallbackLaunchFrame
        )
        guard !states.isEmpty else { return [] }

        let tick: TimeInterval = 1.0 / 60.0
        let maxSimulatedDuration = maxActiveLifetime + 3
        let maxSteps = Int(ceil(maxSimulatedDuration / tick))

        for _ in 0..<maxSteps {
            if states.allSatisfy(\.isSettled) {
                break
            }
            step(states: &states, deltaTime: tick, boardBounds: boardBounds)
        }

        return states
    }

    private static func interleavedLaunchCards(from foundations: [[Card]]) -> [LaunchCard] {
        let maxDepth = foundations.map(\.count).max() ?? 0
        guard maxDepth > 0 else { return [] }

        var cards: [LaunchCard] = []
        cards.reserveCapacity(foundations.reduce(0) { $0 + $1.count })

        for depth in 0..<maxDepth {
            for pile in foundations.indices {
                let reverseIndex = foundations[pile].count - 1 - depth
                guard reverseIndex >= 0 else { continue }
                cards.append(
                    LaunchCard(
                        pile: pile,
                        depth: depth,
                        card: foundations[pile][reverseIndex]
                    )
                )
            }
        }

        return cards
    }
}
