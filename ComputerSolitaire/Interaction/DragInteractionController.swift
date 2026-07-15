import CoreGraphics
import Foundation
import Observation

/// The drag gesture's per-frame state, extracted from ContentView so that
/// per-frame writes invalidate only the views that read them — DragOverlayView
/// and the drop-highlight rows — instead of the whole board tree.
///
/// Only state written on every gesture frame lives here. The flight-boundary
/// state (drop/return offsets, the overlay tilt) stays as `@State` on
/// ContentView: those fields are written with `withAnimation`, and an
/// `@Observable` property loses that transaction when another property has
/// already invalidated the reader in the same tick — the flight would render
/// straight at its destination. `@State` animates per attribute, so the
/// spring survives the surrounding unanimated writes.
@MainActor
@Observable
final class DragInteractionController {
    // Written on every gesture frame; read only by DragOverlayView.
    var dragTranslation: CGSize = .zero

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
    /// stale in-flight drag behind. The flight-boundary fields are cleared by
    /// ContentView's `resetTransientBoardState()` alongside this call.
    func reset() {
        setActiveTarget(nil)
        dragTranslation = .zero
    }
}
