import CoreTransferable
import Foundation
import Observation
import UniformTypeIdentifiers

/// Only references to cards are transferred; the receiving board remains the
/// authority for their values, source, legality, and atomic removal/insertion.
nonisolated struct CardDragItem: Codable, Equatable, Identifiable, Sendable, Transferable {
    let id: UUID
    let dragID: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .solitaireCardDrag)
            .visibility(.ownProcess)
    }
}

extension UTType {
    nonisolated static let solitaireCardDrag = UTType(
        exportedAs: "com.crapshack.ComputerSolitaire.card-drag",
        conformingTo: .data
    )
}

/// One board's native drag transaction. The snapshot and per-drag identity
/// reject cross-window transfers, partial stacks, and delayed callbacks after
/// the player has changed the board, even if an undo restores the same cards.
@Observable
final class DragSessionController {
    private struct PendingDrag {
        let id: UUID
        let state: GameState
        let origin: DragOrigin
        var hasStarted = false
        let selection: Selection
        let items: [CardDragItem]
        var isFinished = false
        var hasEnded = false
    }

    // Payload preparation must not invalidate the source view before SwiftUI
    // creates its drag session. Only the physical interaction is observable.
    @ObservationIgnored private var pending: PendingDrag?
    private(set) var isActive = false
    var dragID: UUID? { pending?.id }

    func prepare(cardIDs: [UUID], in model: SolitaireViewModel) -> [CardDragItem] {
        if let pending, pending.hasStarted, !pending.hasEnded {
            guard cardIDs == [pending.items[0].id],
                  matches(cardIDs: pending.items.map(\.id), in: model) else { return [] }
            return pending.items
        }
        guard !model.isDragging, !model.isWin,
              model.pendingAutoMove == nil,
              model.gameVariant != .golf || !model.golfMatch.isComplete,
              cardIDs.count == 1, let cardID = cardIDs.first,
              let origin = origin(for: cardID, in: model.state),
              let selection = model.dragSelection(from: origin),
              selection.cards.first?.id == cardID else { return [] }
        // Preparing previews can request the same payload repeatedly, or never
        // start a drag. Keep model state untouched until SwiftUI sends .initial.
        if let pending, !pending.hasStarted, !pending.isFinished,
           pending.state == model.state, pending.selection == selection {
            return pending.items
        }
        let id = UUID()
        let items = selection.cards.map { CardDragItem(id: $0.id, dragID: id) }
        pending = PendingDrag(id: id, state: model.state, origin: origin, selection: selection, items: items)
        return items
    }

    @discardableResult
    func activate(in model: SolitaireViewModel, startDrag: (DragOrigin) -> Bool) -> Bool {
        guard let pending, !pending.isFinished, !pending.hasEnded,
              pending.state == model.state else { return false }
        if pending.hasStarted { return matches(cardIDs: pending.items.map(\.id), in: model) }
        guard !model.isDragging, !model.isWin, model.pendingAutoMove == nil,
              startDrag(pending.origin), model.selection == pending.selection else { return false }
        self.pending?.hasStarted = true
        isActive = true
        return true
    }

    func matches(cardIDs: [UUID], in model: SolitaireViewModel) -> Bool {
        guard let pending, pending.hasStarted, !pending.isFinished, model.state == pending.state else { return false }
        if pending.hasEnded {
            guard !model.isDragging, model.selection == nil, model.pendingAutoMove == nil else { return false }
        } else {
            guard model.isDragging, model.selection == pending.selection else { return false }
        }
        // Native drag sessions may enumerate previews in a different order.
        // Validate membership, then apply the original board-ordered selection.
        return cardIDs.count == pending.items.count
            && Set(cardIDs) == Set(pending.items.map(\.id))
    }

    func canDrop(to destination: Destination, in model: SolitaireViewModel) -> Bool {
        guard let pending, matches(cardIDs: pending.items.map(\.id), in: model) else { return false }
        return model.canDrop(pending.selection, to: destination)
    }

    @discardableResult
    func complete(items: [CardDragItem], to destination: Destination, in model: SolitaireViewModel) -> Bool {
        guard let pending, items.allSatisfy({ $0.dragID == pending.id }),
              matches(cardIDs: items.map(\.id), in: model),
              model.canDrop(pending.selection, to: destination) else { return false }
        // The destination performs the entire move exactly once. The source's
        // ended(.move) callback must never remove the cards a second time.
        self.pending?.isFinished = true
        model.selection = pending.selection
        let moved = model.handleDrop(to: destination)
        isActive = false
        if pending.hasEnded { self.pending = nil }
        return moved
    }

    func cancel(in model: SolitaireViewModel) {
        isActive = false
        guard let pending, !pending.isFinished else { return }
        self.pending?.isFinished = true
        if model.isDragging, model.selection == pending.selection {
            model.cancelDrag()
        }
    }

    /// Ending the gesture and receiving its data can happen in either order.
    /// Release interaction state now, but let a late local drop commit only if
    /// this transaction still owns the unchanged board when its payload arrives.
    func finishInteraction(in model: SolitaireViewModel) {
        isActive = false
        guard let pending else { return }
        if pending.isFinished {
            self.pending = nil
        } else {
            self.pending?.hasEnded = true
            if model.isDragging, model.selection == pending.selection { model.cancelDrag() }
        }
    }

    /// Release only when SwiftUI ends the physical session (or its view leaves).
    /// A cancelled transaction must continue refusing payload refreshes until then.
    func end(in model: SolitaireViewModel) {
        cancel(in: model)
        pending = nil
    }

    func invalidateIfBoardChanged(in model: SolitaireViewModel) {
        guard let pending, model.state != pending.state else { return }
        cancel(in: model)
    }

    private func origin(for id: UUID, in state: GameState) -> DragOrigin? {
        if state.waste.last?.id == id { return .waste }
        if state.reserve.last?.id == id { return .reserve }
        for index in state.foundations.indices where state.foundations[index].last?.id == id {
            return .foundation(index)
        }
        for index in state.freeCells.indices where state.freeCells[index]?.id == id {
            return .freeCell(index)
        }
        for pile in state.tableau.indices {
            if let index = state.tableau[pile].firstIndex(where: { $0.id == id }) {
                return .tableau(pile: pile, index: index)
            }
        }
        if let index = state.pyramid.firstIndex(where: { $0?.id == id }) { return .pyramid(index) }
        if let index = state.triPeaks.firstIndex(where: { $0?.id == id }) { return .triPeaks(index) }
        return nil
    }
}
