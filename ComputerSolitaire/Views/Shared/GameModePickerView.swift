import SwiftUI

/// Game switcher presented centered over the board, organized in two levels:
/// a gallery of game families (art, name, description) and — for families
/// with multiple modes — a detail step listing each mode as a full row.
/// The ring plus checkmark mark the current game. Every game auto-resumes,
/// so being mid-game is the unremarkable default and gets no marker; the one
/// badge is "Won" — rare, temporary, and a cue that the game wants a fresh
/// deal. Single-mode games play directly from the gallery. Selection is
/// reported via `onSelect`.
struct GameModePickerView: View {
    struct Entry: Identifiable {
        let mode: GameMode
        let isWon: Bool

        var id: GameMode { mode }
    }

    let entries: [Entry]
    let currentMode: GameMode
    let feltColor: Color
    let cardBackColor: CardBackColor
    let onSelect: (GameMode) -> Void

    /// The family whose modes the detail step shows; nil shows the gallery.
    @State private var drilledFamily: GameVariant?

    var body: some View {
        Group {
            if let family = drilledFamily {
                familyDetail(family)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                familyGallery
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .padding(14)
    }

    // MARK: - Family gallery

    private var familyGallery: some View {
        VStack(spacing: 10) {
            ForEach(GameVariant.allCases, id: \.self) { variant in
                familyCard(variant)
            }
        }
    }

    private func familyCard(_ variant: GameVariant) -> some View {
        let modes = GameMode.modes(for: variant)
        let isMultiMode = modes.count > 1
        let isActiveFamily = currentMode.variant == variant

        return Button {
            if isMultiMode {
                withAnimation(.smooth(duration: 0.25)) {
                    drilledFamily = variant
                }
            } else if let mode = modes.first {
                onSelect(mode)
            }
        } label: {
            HStack(spacing: 12) {
                MiniBoardView(
                    variant: variant,
                    feltColor: feltColor,
                    cardBackColor: cardBackColor,
                    scale: 0.62
                )

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(variant.title)
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .foregroundStyle(.primary)

                        Spacer(minLength: 8)

                        if familyHasWonGame(variant) {
                            wonBadge
                                .fixedSize()
                        }
                    }

                    Text(variant.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if isActiveFamily {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }

                if isMultiMode {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .selectionChip(isSelected: isActiveFamily)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(familyAccessibilityLabel(for: variant))
        .accessibilityAddTraits(isActiveFamily ? .isSelected : [])
    }

    private func familyHasWonGame(_ variant: GameVariant) -> Bool {
        entries.contains { $0.mode.variant == variant && $0.isWon }
    }

    private func familyAccessibilityLabel(for variant: GameVariant) -> String {
        var label = variant.title
        if familyHasWonGame(variant) {
            label += ", Won"
        }
        if currentMode.variant == variant {
            label += ", current game"
        }
        if GameMode.modes(for: variant).count > 1 {
            label += ", opens mode list"
        }
        return label
    }

    // MARK: - Family detail

    private func familyDetail(_ variant: GameVariant) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(.smooth(duration: 0.25)) {
                        drilledFamily = nil
                    }
                } label: {
                    Label("Games", systemImage: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)

                Spacer(minLength: 8)

                Text(variant.title)
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 2)

            HStack(spacing: 12) {
                MiniBoardView(
                    variant: variant,
                    feltColor: feltColor,
                    cardBackColor: cardBackColor
                )

                Text(variant.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }

            VStack(spacing: 8) {
                ForEach(GameMode.modes(for: variant), id: \.self) { mode in
                    modeRow(mode)
                }
            }
        }
    }

    private func modeRow(_ mode: GameMode) -> some View {
        let isActive = mode == currentMode

        return Button {
            onSelect(mode)
        } label: {
            HStack(spacing: 8) {
                Text(mode.optionTitle)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if isWon(mode) {
                    wonBadge
                        .fixedSize()
                }

                if isActive {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .selectionChip(isSelected: isActive)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(modeAccessibilityLabel(for: mode, isActive: isActive))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func modeAccessibilityLabel(for mode: GameMode, isActive: Bool) -> String {
        var label = mode.displayTitle
        if isWon(mode) {
            label += ", Won"
        }
        if isActive {
            label += ", current game"
        }
        return label
    }

    // MARK: - Shared

    private func isWon(_ mode: GameMode) -> Bool {
        entries.first(where: { $0.mode == mode })?.isWon ?? false
    }

    private var wonBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(.yellow)
                .frame(width: 5, height: 5)

            Text("Won")
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(.primary.opacity(0.9))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(.white.opacity(0.1)))
    }
}

/// Centered presentation of the game mode picker over a dimmed board,
/// matching the win overlay's chrome.
struct GameModePickerOverlay: View {
    let entries: [GameModePickerView.Entry]
    let currentMode: GameMode
    let feltColor: Color
    let onSelect: (GameMode) -> Void
    let onDismiss: () -> Void

    @AppStorage(SettingsKey.cardBackColor)
    private var cardBackColorRawValue = CardBackColor.defaultValue.id

    /// The overlay takes keyboard focus while presented so Escape reaches it;
    /// a custom overlay sits outside the window's cancel-action routing that
    /// sheets get for free.
    @FocusState private var isPickerFocused: Bool
    @AccessibilityFocusState private var isPickerAccessibilityFocused: Bool

    var body: some View {
        ZStack {
            // The scrim is the picker's cancel button: clicking outside the
            // panel dismisses, matching a system presentation.
            Button(action: onDismiss) {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss game picker")

            // Short windows (macOS near its minimum size, phone landscape,
            // large accessibility text) can't fit the whole picker; fall back
            // to scrolling the same content rather than clipping it.
            ViewThatFits(in: .vertical) {
                picker

                ScrollView {
                    picker
                }
            }
            .frame(maxWidth: 360)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.3), radius: 24, y: 8)
            )
            .environment(\.colorScheme, .dark)
            .padding(24)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Game picker")
            .accessibilityFocused($isPickerAccessibilityFocused)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityDefaultFocus($isPickerAccessibilityFocused, true)
        .focusable()
        .focusEffectDisabled()
        .focused($isPickerFocused)
        .onKeyPress(.escape) {
            onDismiss()
            return .handled
        }
        .onAppear { isPickerFocused = true }
    }

    private var picker: some View {
        GameModePickerView(
            entries: entries,
            currentMode: currentMode,
            feltColor: feltColor,
            cardBackColor: CardBackColor.from(rawValue: cardBackColorRawValue),
            onSelect: onSelect
        )
    }
}

/// A miniature schematic of a variant's opening layout, drawn with tiny card
/// shapes on a felt swatch.
private struct MiniBoardView: View {
    let variant: GameVariant
    let feltColor: Color
    let cardBackColor: CardBackColor
    var scale: CGFloat = 1

    private enum MiniCard {
        case faceUp
        case faceDown
        case slot
    }

    // The swatches read as a set: one card size and stack offset for every
    // variant, every board spanning the same content width, and the whole
    // board centered in the swatch. Column spacing is the one per-variant
    // knob — it flexes so denser games pack tighter, like the real table.
    private var cardSize: CGSize {
        CGSize(width: 8 * scale, height: 11.5 * scale)
    }

    private var stackOffset: CGFloat {
        4 * scale
    }

    private var contentWidth: CGFloat {
        98 * scale
    }

    private var columnSpacing: CGFloat {
        let columns = CGFloat(variant.boardColumnCount)
        return (contentWidth - (columns * cardSize.width)) / (columns - 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4 * scale) {
            topRow
            switch variant {
            case .pyramid:
                pyramidRows
            case .tripeaks:
                triPeaksRows
            case .canfield:
                canfieldRow
            case .klondike, .spider, .freecell, .yukon, .golf, .fortyThieves, .scorpion:
                tableauRow
            }
        }
        .frame(width: contentWidth)
        .frame(width: 114 * scale, height: 80 * scale)
        .background(
            RoundedRectangle(cornerRadius: 9 * scale, style: .continuous)
                .fill(feltColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 9 * scale, style: .continuous)
                        .fill(.black.opacity(0.1))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9 * scale, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .accessibilityHidden(true)
    }

    private var topRow: some View {
        HStack(spacing: columnSpacing) {
            switch variant {
            case .klondike:
                miniCard(.faceDown)
                miniCard(.slot)
                Spacer(minLength: 0)
                foundationSlots(count: 4)
            case .freecell:
                foundationSlots(count: 4)
                Spacer(minLength: 0)
                foundationSlots(count: 4)
            case .yukon:
                Spacer(minLength: 0)
                foundationSlots(count: 4)
            case .spider:
                miniCard(.faceDown)
                Spacer(minLength: 0)
                foundationSlots(count: 8)
            case .fortyThieves:
                miniCard(.faceDown)
                miniCard(.slot)
                foundationSlots(count: 8)
            case .scorpion:
                miniCard(.faceDown)
                Spacer(minLength: 0)
                foundationSlots(count: 4)
            case .pyramid:
                miniCard(.faceDown)
                miniCard(.slot)
                Spacer(minLength: 0)
                miniCard(.slot)
            case .tripeaks, .golf:
                miniCard(.faceDown)
                miniCard(.faceUp)
                Spacer(minLength: 0)
            case .canfield:
                miniCard(.faceDown)
                miniCard(.slot)
                Spacer(minLength: 0)
                miniCard(.faceUp)
                foundationSlots(count: 3)
            }
        }
    }

    private func foundationSlots(count: Int) -> some View {
        ForEach(0..<count, id: \.self) { _ in
            miniCard(.slot)
        }
    }

    /// TriPeaks' three face-down peaks over their shared face-up base row.
    /// Peak positions derive from the base-row pitch: each card sits centered
    /// over the two it covers, exactly like `TriPeaksGeometry` lays out the
    /// real board.
    private var triPeaksRows: some View {
        let unit = cardSize.width + columnSpacing
        return VStack(alignment: .leading, spacing: stackOffset - cardSize.height) {
            HStack(spacing: (3 * unit) - cardSize.width) {
                ForEach(0..<3, id: \.self) { _ in
                    miniCard(.faceDown)
                }
            }
            .padding(.leading, 1.5 * unit)

            HStack(spacing: unit + columnSpacing) {
                ForEach(0..<3, id: \.self) { _ in
                    HStack(spacing: columnSpacing) {
                        miniCard(.faceDown)
                        miniCard(.faceDown)
                    }
                }
            }
            .padding(.leading, unit)

            HStack(spacing: columnSpacing) {
                ForEach(0..<9, id: \.self) { _ in
                    miniCard(.faceDown)
                }
            }
            .padding(.leading, unit / 2)

            HStack(spacing: columnSpacing) {
                ForEach(0..<10, id: \.self) { _ in
                    miniCard(.faceUp)
                }
            }
        }
    }

    /// Pyramid's card triangle (abridged to its top rows), centered like the
    /// real board's.
    private var pyramidRows: some View {
        VStack(spacing: stackOffset - cardSize.height) {
            ForEach(1..<7, id: \.self) { rowCount in
                HStack(spacing: columnSpacing) {
                    ForEach(0..<rowCount, id: \.self) { _ in
                        miniCard(.faceUp)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Canfield's tableau band: the face-down reserve at the left, then the
    /// four single-card piles under the foundations — the base card renders
    /// face up in `topRow`'s first foundation slot.
    private var canfieldRow: some View {
        HStack(alignment: .top, spacing: columnSpacing) {
            miniCard(.faceDown)
            Spacer(minLength: 0)
            ForEach(0..<4, id: \.self) { _ in
                miniCard(.faceUp)
            }
        }
    }

    private var tableauRow: some View {
        HStack(alignment: .top, spacing: columnSpacing) {
            ForEach(tableauColumns.indices, id: \.self) { columnIndex in
                VStack(spacing: stackOffset - cardSize.height) {
                    ForEach(tableauColumns[columnIndex].indices, id: \.self) { cardIndex in
                        miniCard(tableauColumns[columnIndex][cardIndex])
                    }
                }
            }
        }
    }

    /// The opening tableau, abridged so every variant's silhouette stays
    /// recognizable inside the fixed swatch.
    private var tableauColumns: [[MiniCard]] {
        switch variant {
        case .klondike:
            return (0..<7).map { column in
                Array(repeating: .faceDown, count: column) + [.faceUp]
            }
        case .freecell:
            return Array(repeating: Array(repeating: .faceUp, count: 7), count: 8)
        case .yukon:
            return [[.faceUp]] + (1..<7).map { column in
                Array(repeating: .faceDown, count: min(column, 3))
                    + Array(repeating: .faceUp, count: 5)
            }
        case .spider:
            return (0..<10).map { column in
                Array(repeating: .faceDown, count: column < 4 ? 5 : 4) + [.faceUp]
            }
        case .golf:
            return Array(repeating: Array(repeating: .faceUp, count: 5), count: 7)
        case .fortyThieves:
            return Array(repeating: Array(repeating: .faceUp, count: 4), count: 10)
        case .scorpion:
            return (0..<7).map { column in
                column < 4
                    ? Array(repeating: .faceDown, count: 3) + Array(repeating: .faceUp, count: 4)
                    : Array(repeating: .faceUp, count: 7)
            }
        case .pyramid, .tripeaks, .canfield:
            // Pyramid, TriPeaks, and Canfield draw their boards through their
            // own row builders.
            return []
        }
    }

    private func miniCard(_ kind: MiniCard) -> some View {
        RoundedRectangle(cornerRadius: 2 * scale, style: .continuous)
            .fill(fillStyle(for: kind))
            .overlay(
                RoundedRectangle(cornerRadius: 2 * scale, style: .continuous)
                    .stroke(
                        style: StrokeStyle(
                            lineWidth: 0.75,
                            dash: kind == .slot ? [1.5, 1.5] : []
                        )
                    )
                    .foregroundStyle(strokeStyle(for: kind))
            )
            .frame(width: cardSize.width, height: cardSize.height)
    }

    private func fillStyle(for kind: MiniCard) -> AnyShapeStyle {
        switch kind {
        case .faceUp:
            return AnyShapeStyle(.white.opacity(0.95))
        case .faceDown:
            return AnyShapeStyle(cardBackColor.swatch)
        case .slot:
            return AnyShapeStyle(.white.opacity(0.06))
        }
    }

    private func strokeStyle(for kind: MiniCard) -> AnyShapeStyle {
        switch kind {
        case .faceUp:
            return AnyShapeStyle(.black.opacity(0.35))
        case .faceDown:
            return AnyShapeStyle(.white.opacity(0.35))
        case .slot:
            return AnyShapeStyle(.white.opacity(0.4))
        }
    }
}
