import CoreGraphics
import Foundation
import Observation

/// The drag gesture's fast-changing state, extracted from ContentView so that
/// per-frame writes invalidate only the views that read them — DragOverlayView
/// — instead of the whole board tree. Deliberately a state bag, not an
/// orchestrator: the drop/return/auto-move flows stay on ContentView, which
/// fuses this state with card frames, tilts, sounds, and the session.
@MainActor
@Observable
final class DragInteractionController {
    // Written on every gesture frame; read only by DragOverlayView.
    var dragTranslation: CGSize = .zero
    var overlayTilt: Double = 0

    // Drop/return transition state; changes at flight boundaries.
    var dragReturnOffset: CGSize = .zero
    var isReturningDrag = false
    var returningCards: [Card] = []
    var isDroppingCards = false
    var droppingSelection: Selection?
    var dropAnimationOffset: CGSize = .zero
    var pendingDropDestination: Destination?
    var wasteReturnAnchorCardID: UUID?
    var wasteReturnAnchorFrame: CGRect?

    private(set) var activeTarget: DropTarget?

    /// The gesture calls this every frame. Unlike `@State`, `@Observable`
    /// fires on every set with no equal-value dedupe, and the board rows read
    /// `activeTarget` for drop highlighting — the guard keeps their
    /// invalidation to actual target crossings.
    func setActiveTarget(_ target: DropTarget?) {
        guard target != activeTarget else { return }
        activeTarget = target
    }

    /// Clears every field, so a game switch or new deal can never leave a
    /// stale in-flight drag behind. Mirrors the drag portion of ContentView's
    /// `resetTransientBoardState()`.
    func reset() {
        setActiveTarget(nil)
        dragTranslation = .zero
        overlayTilt = 0
        dragReturnOffset = .zero
        isReturningDrag = false
        returningCards = []
        isDroppingCards = false
        droppingSelection = nil
        dropAnimationOffset = .zero
        pendingDropDestination = nil
        wasteReturnAnchorCardID = nil
        wasteReturnAnchorFrame = nil
    }
}
