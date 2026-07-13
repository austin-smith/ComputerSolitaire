import SwiftUI

extension View {
    /// The app's selectable-card chrome: rounded rectangle with an accent tint
    /// and stroke when selected. Used by settings chips and the game mode picker.
    func selectionChip(isSelected: Bool) -> some View {
        self
            .padding(.vertical, 10)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        isSelected
                            ? AnyShapeStyle(Color.accentColor.opacity(0.12))
                            : AnyShapeStyle(.quaternary.opacity(0.5))
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isSelected ? Color.accentColor : Color.primary.opacity(0.1),
                        lineWidth: isSelected ? 2 : 1
                    )
            }
            .opacity(isSelected ? 1 : 0.75)
            .contentShape(Rectangle())
    }
}
