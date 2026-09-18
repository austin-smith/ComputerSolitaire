import SwiftUI

extension View {
    /// Keep the availability decision identical for sources and destination.
    /// Attach before opacity/offset so native previews capture the visible card.
    @ViewBuilder
    func cardDrag(cardID: UUID, gesture: AnyGesture<DragGesture.Value>, isEnabled: Bool = true) -> some View {
        if #available(iOS 27, macOS 27, *) {
            if isEnabled {
                draggable(containerItemID: cardID)
            } else {
                self
            }
        } else {
            self.gesture(gesture, including: isEnabled ? .all : .subviews)
        }
    }
}

struct CardBoardDragModifier: ViewModifier {
    let model: SolitaireViewModel
    let controller: DragSessionController
    let drag: DragInteractionController
    let dropFrames: [DropTarget: DropTargetGeometry]
    let isEnabled: Bool
    let startDrag: (DragOrigin) -> Bool
    let didFinish: (Bool) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 27, macOS 27, *) {
            content.modifier(BoardDragSessionModifier(
                model: model, controller: controller, drag: drag,
                dropFrames: dropFrames, isEnabled: isEnabled,
                startDrag: startDrag, didFinish: didFinish
            ))
        } else {
            content
        }
    }
}

@available(iOS 27, macOS 27, *)
private struct BoardDragSessionModifier: ViewModifier {
    let model: SolitaireViewModel
    let controller: DragSessionController
    let drag: DragInteractionController
    let dropFrames: [DropTarget: DropTargetGeometry]
    let isEnabled: Bool
    let startDrag: (DragOrigin) -> Bool
    let didFinish: (Bool) -> Void
    @State private var sessionID: DragSession.ID?
    @State private var dragID: UUID?

    func body(content: Content) -> some View {
        let board = content
            .dragContainer(for: CardDragItem.self) { (ids: [UUID]) in
                guard isEnabled else { return [CardDragItem]() }
                return controller.prepare(cardIDs: ids, in: model)
            }
            .dragConfiguration(configuration)
            .onDragSessionUpdated(handleDragSession)
            .dropDestination(for: CardDragItem.self) { items, session in
                guard let target = target(for: session),
                      controller.complete(items: items, to: target.destination, in: model) else {
                    return
                }
                drag.setActiveTarget(nil)
                didFinish(true)
            }
            .dropConfiguration { session in
                let allowed = target(for: session).map { controller.canDrop(to: $0.destination, in: model) } ?? false
                return DropConfiguration(operation: allowed ? .move : .forbidden)
            }
            .onDropSessionUpdated { session in
                switch session.phase {
                case .entering, .active:
                    let target = target(for: session)
                    if target != drag.activeTarget, let target, controller.canDrop(to: target.destination, in: model) {
                        HapticManager.shared.play(.dropTargetAcquired)
                    }
                    drag.setActiveTarget(target)
                case .exiting, .ended, .dataTransferCompleted:
                    drag.setActiveTarget(nil)
                @unknown default:
                    drag.setActiveTarget(nil)
                }
            }
#if os(macOS)
        // Preview formations are macOS-only in the installed SDK. iOS uses
        // the system's native multi-item presentation.
        board.dragPreviewsFormation(.stack).dropPreviewsFormation(.stack)
#else
        board
#endif
    }

    private var configuration: DragConfiguration {
#if os(macOS)
        DragConfiguration(
            operationsWithinApp: .init(allowCopy: false, allowMove: true),
            operationsOutsideApp: .init(allowCopy: false)
        )
#else
        DragConfiguration(
            operationsWithinApp: .init(allowMove: true),
            operationsOutsideApp: .init(allowCopy: false)
        )
#endif
    }

    private func target(for session: DropSession) -> DropTarget? {
        guard session.suggestedOperations.contains(.move),
              let local = session.localSession,
              controller.matches(cardIDs: local.draggedItemIDs(for: UUID.self), in: model) else { return nil }
        return DragDropCoordinator.resolveDropTarget(
            at: session.location, dropFrames: dropFrames,
            canDrop: { controller.canDrop(to: $0.destination, in: model) }
        )
    }

    private func handleDragSession(_ session: DragSession) {
        switch session.phase {
        case .initial:
            guard controller.activate(in: model, startDrag: startDrag) else { return }
            sessionID = session.id
            dragID = controller.dragID
        case .ended(let operation):
            guard session.id == sessionID, dragID == controller.dragID else { return }
            if operation == .move {
                controller.finishInteraction(in: model)
                drag.setActiveTarget(nil)
            } else {
                endSession()
            }
        case .dataTransferCompleted:
            // macOS may transfer data while preparing the drag, before it
            // becomes active. This phase does not end the physical interaction.
            break
        default:
            break
        }
    }

    private func endSession() {
        let wasActive = controller.isActive
        controller.end(in: model)
        drag.setActiveTarget(nil)
        if wasActive { didFinish(false) }
    }
}
