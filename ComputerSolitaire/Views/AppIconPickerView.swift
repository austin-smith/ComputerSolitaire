#if os(iOS)
import SwiftUI
import UIKit

/// To add a new alternate icon:
/// 1. Add its Icon Composer package to `AppIcons/`.
/// 2. Append the icon name to `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` in build settings.
/// 3. Add a flattened preview export to `Assets.xcassets/AppIconPreviews/` and declare it below.
struct AppIcon: Identifiable, Equatable {
    /// The name passed to `setAlternateIconName(_:)`; `nil` selects the primary icon.
    let alternateIconName: String?
    let name: String
    let previewImageName: String

    var id: String { previewImageName }

    static let `default` = AppIcon(
        alternateIconName: nil,
        name: "Default",
        previewImageName: "AppIconPreviewDefault"
    )

    static let queenOfHearts = AppIcon(
        alternateIconName: "QueenOfHeartsAppIcon",
        name: "Queen of Hearts",
        previewImageName: "AppIconPreviewQueenOfHearts"
    )

    static let all: [AppIcon] = [.default, .queenOfHearts]

    static func current() -> AppIcon {
        let activeName = UIApplication.shared.alternateIconName
        return all.first { $0.alternateIconName == activeName } ?? .default
    }
}

struct AppIconPreviewView: View {
    let icon: AppIcon
    var size: CGFloat = 56

    private var shape: RoundedRectangle {
        // Matches the home screen icon corner radius ratio.
        RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
    }

    var body: some View {
        Image(icon.previewImageName)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(shape)
            .accessibilityHidden(true)
            .overlay {
                shape.stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
            }
    }
}

struct AppIconPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: AppIcon

    private let columns = [GridItem(.adaptive(minimum: 130), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(AppIcon.all) { icon in
                    iconTile(icon)
                }
            }
            .padding(24)
        }
        .navigationTitle("App Icon")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
    }

    private func iconTile(_ icon: AppIcon) -> some View {
        let isSelected = selection == icon

        return Button {
            guard !isSelected else { return }
            HapticManager.shared.play(.settingsSelection)
            let previous = selection
            withAnimation(.smooth(duration: 0.3)) {
                selection = icon
            }
            UIApplication.shared.setAlternateIconName(icon.alternateIconName) { error in
                guard error != nil else { return }
                Task { @MainActor in
                    withAnimation(.smooth(duration: 0.3)) {
                        selection = previous
                    }
                }
            }
        } label: {
            VStack(spacing: 6) {
                AppIconPreviewView(icon: icon)

                Text(icon.name)
                    .font(.caption.weight(.bold))
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? .thickMaterial : .thinMaterial)
                    .shadow(
                        color: .black.opacity(isSelected ? 0.12 : 0.04),
                        radius: isSelected ? 8 : 2,
                        y: isSelected ? 4 : 1
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        Color.accentColor.opacity(isSelected ? 1 : 0),
                        lineWidth: 2.5
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        Color.primary.opacity(isSelected ? 0 : 0.1),
                        lineWidth: 1
                    )
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.accentColor)
                        .padding(6)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(icon.name) app icon")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    NavigationStack {
        AppIconPickerView(selection: .constant(.default))
    }
}
#endif
