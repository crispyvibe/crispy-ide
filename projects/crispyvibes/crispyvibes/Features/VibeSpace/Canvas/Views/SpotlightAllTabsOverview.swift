import SwiftUI

@MainActor
struct SpotlightAllTabsOverview: View {
    @Environment(\.appThemePalette) private var palette
    let catalog: SpotlightMetadataCatalog
    let snapshot: SpotlightLayoutSnapshot
    let currentID: SpotlightPersistentItemID?
    let focusedID: SpotlightPersistentItemID?
    let onSelect: (SpotlightNavigationIdentity) -> Void
    let onDismiss: () -> Void

    @State private var query = ""
    @State private var selectedID: SpotlightPersistentItemID?
    @State private var hoveredPositionID: UUID?
    @FocusState private var searchFocused: Bool

    private struct Suggestion: Identifiable {
        let position: SpotlightPositionSnapshot
        let members: [SpotlightItemMetadata]
        var id: UUID { position.id }
    }

    private var filteredMembers: [SpotlightItemMetadata] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayed = snapshot.flattenedMembers.compactMap { catalog.byID[$0] }
        guard !needle.isEmpty else { return displayed }
        return displayed.filter {
            [$0.title, $0.secondary, $0.group]
                .joined(separator: " ")
                .localizedCaseInsensitiveContains(needle)
        }
    }

    private var suggestions: [Suggestion] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchingIDs = Set(filteredMembers.map(\.id))
        return snapshot.positions.compactMap { position in
            guard needle.isEmpty || position.members.contains(where: matchingIDs.contains) else {
                return nil
            }
            let members = position.members.compactMap { catalog.byID[$0] }
            guard !members.isEmpty else { return nil }
            return Suggestion(position: position, members: members)
        }
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(minimum: 210, maximum: 340), spacing: 18),
            count: 3
        )
    }

    var body: some View {
        VStack(spacing: 20) {
            searchBar
            if suggestions.isEmpty {
                ContentUnavailableView(
                    AppStrings.Spotlight.noMatches,
                    systemImage: "magnifyingglass"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                suggestionGrid
            }
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 28)
        .frame(maxWidth: 1080, maxHeight: 760)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("spotlight.overview")
        .onAppear {
            selectedID = filteredMembers.first(where: { $0.id == focusedID })?.id
                ?? filteredMembers.first?.id
            DispatchQueue.main.async { searchFocused = true }
        }
        .onChange(of: query) { _, _ in
            if !filteredMembers.contains(where: { $0.id == selectedID }) {
                selectedID = filteredMembers.first?.id
            }
        }
        .onMoveCommand { direction in
            moveSelection(direction)
        }
        .onExitCommand(perform: onDismiss)
    }

    private var searchBar: some View {
        HStack(spacing: 11) {
            Image(systemName: "magnifyingglass")
                .font(AppTypographyTokens.scaledSystem(15, weight: .medium))
                .foregroundStyle(palette.secondaryTextColor)
            TextField(AppStrings.Spotlight.searchPlaceholder, text: $query)
                .textFieldStyle(.plain)
                .font(AppTypographyTokens.body)
                .focused($searchFocused)
                .onSubmit(performSelection)
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(AppTypographyTokens.scaledSystem(14, weight: .medium))
                    .foregroundStyle(palette.secondaryTextColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppStrings.Common.close)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: 620)
        .frame(height: 48)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .background(
            palette.canvasSecondaryBackgroundColor.opacity(0.84),
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .stroke(palette.borderColorValue.opacity(0.65), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
    }

    private var suggestionGrid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, alignment: .center, spacing: 18) {
                    ForEach(suggestions) { suggestion in
                        suggestionTile(suggestion)
                    }
                }
                .padding(12)
            }
            .scrollIndicators(.hidden)
            .onChange(of: selectedID) { _, id in
                guard let id,
                      let positionID = snapshot.position(containing: id)?.id else { return }
                proxy.scrollTo(positionID, anchor: .center)
            }
        }
    }

    private func suggestionTile(_ suggestion: Suggestion) -> some View {
        let isCurrent = suggestion.position.members.contains(where: { $0 == currentID })
        let isSelected = suggestion.position.members.contains(where: { $0 == selectedID })
        let isHovered = hoveredPositionID == suggestion.id

        return ZStack {
            if suggestion.position.isCombo {
                comboThumbnail(suggestion)
            } else if let member = suggestion.members.first {
                memberThumbnail(member, position: suggestion.position, fillsComboHalf: false)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .background(
            (isCurrent || isSelected ? palette.selectionBackgroundColor : palette.canvasSecondaryBackgroundColor)
                .opacity(isHovered ? 0.96 : 0.82)
        )
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(alignment: .topLeading) {
            if isCurrent {
                Text(AppStrings.Spotlight.current)
                    .font(AppTypographyTokens.caption2Semibold)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 8)
                    .frame(height: 23)
                    .background(Color.black.opacity(0.66), in: Capsule())
                    .padding(9)
            }
        }
        .scaleEffect(isHovered ? 1.025 : 1)
        .shadow(color: .black.opacity(isHovered ? 0.34 : 0.18), radius: isHovered ? 18 : 9, y: isHovered ? 10 : 5)
        .animation(.easeOut(duration: 0.16), value: isHovered)
        .onHover { hoveredPositionID = $0 ? suggestion.id : nil }
        .accessibilityElement(children: .contain)
        .accessibilityValue(
            [
                suggestion.position.isCombo ? AppStrings.Spotlight.combo : nil,
                isCurrent ? AppStrings.Spotlight.current : nil,
            ].compactMap { $0 }.joined(separator: ", ")
        )
    }

    private func comboThumbnail(_ suggestion: Suggestion) -> some View {
        ZStack(alignment: .topTrailing) {
            HStack(spacing: 2) {
                ForEach(suggestion.members, id: \.safeAccessibilityID) { member in
                    memberThumbnail(member, position: suggestion.position, fillsComboHalf: true)
                        .id(member.id)
                }
            }
            Label(AppStrings.Spotlight.combo, systemImage: "link")
                .font(AppTypographyTokens.caption2Semibold)
                .foregroundStyle(Color.white)
                .padding(.horizontal, 8)
                .frame(height: 23)
                .background(Color.black.opacity(0.66), in: Capsule())
                .padding(9)
        }
    }

    private func memberThumbnail(
        _ entry: SpotlightItemMetadata,
        position: SpotlightPositionSnapshot,
        fillsComboHalf: Bool
    ) -> some View {
        let isFocused = entry.id == focusedID
        return Button {
            selectedID = entry.id
            onSelect(entry.item.navigationIdentity)
        } label: {
            ZStack {
                thumbnailArtwork(for: entry, compact: fillsComboHalf)
                Rectangle()
                    .fill(palette.canvasBackgroundColor.opacity(0.82))
                    .frame(height: 56)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                VStack {
                    Spacer()
                    HStack(alignment: .bottom, spacing: 7) {
                        Image(systemName: entry.iconName)
                            .font(AppTypographyTokens.scaledSystem(12, weight: .semibold))
                            .foregroundStyle(entry.accentColor ?? Color.white)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(displayTitle(for: entry))
                                .font(AppTypographyTokens.subheadlineSemibold)
                                .lineLimit(1)
                            if entry.secondary != entry.title {
                                Text(entry.secondary)
                                    .font(AppTypographyTokens.caption2)
                                    .foregroundStyle(Color.white.opacity(0.7))
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                        if isFocused {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(entry.accentColor ?? palette.accentColor)
                        }
                    }
                    .foregroundStyle(Color.white)
                    .padding(11)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppStrings.Spotlight.itemAccessibilityLabel(displayTitle(for: entry), entry.secondary))
        .accessibilityValue(accessibilityValue(position: position, isFocused: isFocused))
        .accessibilityIdentifier("spotlight.overview.item.\(entry.safeAccessibilityID)")
    }

    @ViewBuilder
    private func thumbnailArtwork(for entry: SpotlightItemMetadata, compact: Bool) -> some View {
        SpotlightOverviewArtwork(entry: entry, compact: compact)
    }

    private func displayTitle(for entry: SpotlightItemMetadata) -> String {
        catalog.displayTitle(for: entry)
    }

    private func accessibilityValue(
        position: SpotlightPositionSnapshot,
        isFocused: Bool
    ) -> String {
        [
            position.isCombo ? AppStrings.Spotlight.combo : nil,
            currentID.map(position.members.contains) == true ? AppStrings.Spotlight.current : nil,
            isFocused ? AppStrings.Spotlight.focused : nil,
        ].compactMap { $0 }.joined(separator: ", ")
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard !suggestions.isEmpty else { return }
        guard let selectedID,
              let positionIndex = suggestions.firstIndex(where: { $0.position.members.contains(selectedID) }) else {
            self.selectedID = suggestions.first?.members.first?.id
            return
        }

        let currentMembers = suggestions[positionIndex].members
        let memberIndex = currentMembers.firstIndex(where: { $0.id == selectedID }) ?? 0

        switch direction {
        case .left:
            if memberIndex > 0 {
                self.selectedID = currentMembers[memberIndex - 1].id
            } else if positionIndex > 0 {
                self.selectedID = suggestions[positionIndex - 1].members.last?.id
            }
        case .right:
            if memberIndex + 1 < currentMembers.count {
                self.selectedID = currentMembers[memberIndex + 1].id
            } else if positionIndex + 1 < suggestions.count {
                self.selectedID = suggestions[positionIndex + 1].members.first?.id
            }
        case .up, .down:
            let targetIndex = positionIndex + (direction == .up ? -3 : 3)
            guard suggestions.indices.contains(targetIndex) else { return }
            let targetMembers = suggestions[targetIndex].members
            self.selectedID = targetMembers[min(memberIndex, targetMembers.count - 1)].id
        default:
            break
        }
    }

    private func performSelection() {
        guard let selectedID,
              let entry = catalog.byID[selectedID],
              suggestions.contains(where: { $0.position.members.contains(selectedID) }) else { return }
        onSelect(entry.item.navigationIdentity)
    }
}
