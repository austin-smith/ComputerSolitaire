import Foundation

extension SolitaireViewModel {
    func applyYukonMoveScore(for source: Selection.Source, destination: Destination) {
        switch (source, destination) {
        case (.tableau, .foundation):
            applyScore(.tableauToFoundation)
        case (.foundation, .tableau):
            applyScore(.foundationToTableau)
        default:
            break
        }
    }
}
