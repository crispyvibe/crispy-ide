import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct SpotlightTabShelf: View {
    @Environment(\.appThemePalette) private var palette
    let coordinator: TerminalSpotlightCoordinator
    let catalog: SpotlightMetadataCatalog
    let snapshot: SpotlightLayoutSnapshot
    let hostID: String
    let generation: UInt64
    let currentID: SpotlightPersistentItemID?
    let focusedID: SpotlightPersistentItemID?
    let onSelect: (SpotlightNavigationIdentity) -> Void
    let onCommit: (SpotlightLayoutSnapshot) -> Void
    let resolveCurrentLayout: () -> SpotlightLayoutSnapshot
    let onShowAll: () -> Void

    @State private var draggedPayload: SpotlightDragPayload?
    @State private var dropTarget: DropTarget?
    @State private var hoveredPositionID: UUID?
    @State private var pendingSelectionWorkItem: DispatchWorkItem?
    @FocusState private var keyboardFocusedID: SpotlightPersistentItemID?

    private struct DropTarget: Equatable {
        let positionID: UUID
        let zone: SpotlightDropZone
    }

    private var metadataByID: [SpotlightPersistentItemID: SpotlightItemMetadata] {
        catalog.byID
    }

    private func displayTitle(for entry: SpotlightItemMetadata) -> String {
        catalog.displayTitle(for: entry)
    }

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 6) {
                        ForEach(snapshot.positions) { position in
                            positionChip(position)
                                .id(position.id)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 10)
                    .background(SpotlightShelfScrollRegistration(coordinator: coordinator))
                }
                // A horizontal ScrollView otherwise accepts the parent's unlimited
                // vertical proposal and centers its chips inside the entire card.
                // Keep the shelf as compact chrome so content starts immediately below it.
                .frame(height: 44)
                .scrollTargetBehavior(.viewAligned(limitBehavior: .always))
                .onAppear { scrollCurrentPosition(proxy) }
                .onChange(of: currentID) { _, _ in scrollCurrentPosition(proxy) }
            }

            Divider()
                .frame(height: 20)
                .opacity(0.55)

            Button(action: onShowAll) {
                HStack(spacing: 6) {
                    Image(systemName: "square.grid.2x2")
                    Text("\(catalog.ordered.count)")
                        .monospacedDigit()
                }
                .font(AppTypographyTokens.captionSemibold)
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(
                    palette.canvasBackgroundColor.opacity(0.5),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.secondaryTextColor)
            .help(AppStrings.Spotlight.allTabsHelp)
            .accessibilityLabel(AppStrings.Spotlight.allTabs)
            .accessibilityIdentifier("spotlight.shelf.all-tabs")
            .padding(.horizontal, 8)
            .background(SpotlightShelfHitRegionRegistration(coordinator: coordinator, isExcluded: true))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(SpotlightShelfHitRegionRegistration(coordinator: coordinator, isExcluded: false))
        .background {
            UnevenRoundedRectangle(
                cornerRadii: RectangleCornerRadii(topLeading: 11, bottomLeading: 0, bottomTrailing: 0, topTrailing: 11),
                style: .continuous
            )
            .fill(palette.canvasSecondaryBackgroundColor.opacity(0.96))
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.borderColorValue.opacity(0.7)).frame(height: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("spotlight.navigation.tab-shelf")
    }

    private func positionChip(_ position: SpotlightPositionSnapshot) -> some View {
        let isCurrent = currentID.map(position.members.contains) == true
        return HStack(spacing: 3) {
            if position.isCombo {
                Image(systemName: "line.3.horizontal")
                    .font(AppTypographyTokens.scaledSystem(9, weight: .semibold))
                    .foregroundStyle(palette.secondaryTextColor)
                    .frame(width: 28, height: 30)
                    .contentShape(Rectangle())
                    .onDrag { dragProvider(subject: .position(position.id)) }
                    .help(AppStrings.Spotlight.dragCombo)
            }

            ForEach(position.members, id: \.self) { memberID in
                if let entry = metadataByID[memberID] {
                    memberChip(entry, position: position)
                }
            }
        }
        .padding(.horizontal, position.isCombo ? 4 : 2)
        .padding(.vertical, 2)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(
                    isCurrent
                        ? palette.selectionBackgroundColor.opacity(0.32)
                        : hoveredPositionID == position.id
                            ? palette.canvasBackgroundColor.opacity(0.38)
                            : Color.clear
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(
                    isCurrent ? palette.accentColor.opacity(0.72) : Color.clear,
                    lineWidth: isCurrent ? 1.25 : 0
                )
        }
        .overlay { dropIndicator(position) }
        .opacity(isDragged(position) ? 0.58 : 1)
        .background {
            GeometryReader { proxy in
                Color.clear.onDrop(
                    of: [UTType.data],
                    delegate: ShelfDropDelegate(
                        positionID: position.id,
                        size: proxy.size,
                        onHover: { dropTarget = $0.map { DropTarget(positionID: position.id, zone: $0) } },
                        onDrop: performDrop
                    )
                )
            }
        }
        .onHover { isHovering in
            hoveredPositionID = isHovering ? position.id : (hoveredPositionID == position.id ? nil : hoveredPositionID)
        }
        .animation(.easeInOut(duration: 0.12), value: dropTarget)
    }

    private func memberChip(
        _ entry: SpotlightItemMetadata,
        position: SpotlightPositionSnapshot
    ) -> some View {
        let isFocused = entry.id == focusedID
        return Button {
            scheduleSelection(entry.item.navigationIdentity)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: entry.iconName)
                    .font(AppTypographyTokens.scaledSystem(10, weight: .medium))
                    .foregroundStyle(entry.accentColor ?? palette.accentColor)
                Text(displayTitle(for: entry))
                    .font(AppTypographyTokens.captionSemibold)
                    .lineLimit(1)
                if position.isCombo && isFocused {
                    Circle()
                        .fill(palette.accentColor)
                        .frame(width: 5, height: 5)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(palette.primaryTextColor)
            .padding(.horizontal, 8)
            .frame(height: 30)
            .frame(minWidth: 76, maxWidth: 168, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .focused($keyboardFocusedID, equals: entry.id)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(keyboardFocusedID == entry.id ? palette.selectionBackgroundColor.opacity(0.55) : .clear)
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                pendingSelectionWorkItem?.cancel()
                pendingSelectionWorkItem = nil
                onShowAll()
            }
        )
        .overlay {
            if let activityState = entry.activityState {
                SpotlightShelfTerminalActivity(
                    activityState: activityState,
                    color: entry.accentColor ?? palette.accentColor
                )
            }
        }
        .accessibilityLabel(AppStrings.Spotlight.itemAccessibilityLabel(displayTitle(for: entry), entry.secondary))
        .accessibilityValue(
            [
                position.isCombo ? AppStrings.Spotlight.combo : nil,
                entry.activityState?.isActive == true ? AppStrings.Spotlight.active : nil,
            ].compactMap { $0 }.joined(separator: ", ")
        )
        .accessibilityIdentifier("spotlight.shelf.item.\(entry.safeAccessibilityID)")
        .onDrag {
            dragProvider(subject: .member(entry.id, positionID: position.id))
        }
    }

    private func dragProvider(subject: SpotlightDragSubject) -> NSItemProvider {
        let payload = SpotlightDragPayload(hostID: hostID, generation: generation, subject: subject)
        draggedPayload = payload
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: UTType.data.identifier, visibility: .ownProcess) { completion in
            completion(try? JSONEncoder().encode(payload), nil)
            return nil
        }
        return provider
    }

    private func performDrop(positionID: UUID, zone: SpotlightDropZone, providers: [NSItemProvider]) -> Bool {
        defer {
            draggedPayload = nil
            dropTarget = nil
        }
        if let draggedPayload {
            return commit(payload: draggedPayload, positionID: positionID, zone: zone)
        }
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.data.identifier) }) else {
            return false
        }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.data.identifier) { data, _ in
            guard let data, let payload = try? JSONDecoder().decode(SpotlightDragPayload.self, from: data) else { return }
            Task { @MainActor in
                _ = commit(payload: payload, positionID: positionID, zone: zone)
            }
        }
        return true
    }

    private func commit(payload: SpotlightDragPayload, positionID: UUID, zone: SpotlightDropZone) -> Bool {
        let liveGeneration = coordinator.layoutGeneration
        guard payload.generation == liveGeneration else { return false }
        let liveSnapshot = resolveCurrentLayout()
        guard let result = SpotlightLayoutReducer.dropping(
            payload: payload,
            on: positionID,
            zone: zone,
            snapshot: liveSnapshot,
            hostID: hostID,
            generation: liveGeneration
        ) else { return false }
        onCommit(result)
        return true
    }

    private func isDragged(_ position: SpotlightPositionSnapshot) -> Bool {
        switch draggedPayload?.subject {
        case let .position(id): return id == position.id
        case let .member(member, _): return position.members.contains(member)
        case nil: return false
        }
    }

    @ViewBuilder
    private func dropIndicator(_ position: SpotlightPositionSnapshot) -> some View {
        if let dropTarget, dropTarget.positionID == position.id {
            GeometryReader { proxy in
                switch dropTarget.zone {
                case .before, .after:
                    Capsule()
                        .fill(palette.accentColor)
                        .frame(width: 2, height: max(12, proxy.size.height - 4))
                        .position(x: dropTarget.zone == .before ? 1 : proxy.size.width - 1, y: proxy.size.height / 2)
                case .club:
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(palette.accentColor, lineWidth: 2)
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func scheduleSelection(_ identity: SpotlightNavigationIdentity) {
        pendingSelectionWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            pendingSelectionWorkItem = nil
            onSelect(identity)
        }
        pendingSelectionWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: workItem)
    }

    private func scrollCurrentPosition(_ proxy: ScrollViewProxy) {
        guard let currentID,
              let positionID = snapshot.position(containing: currentID)?.id else { return }
        let expectedID = currentID
        let expectedGeneration = generation
        DispatchQueue.main.async {
            guard coordinator.layoutGeneration == expectedGeneration,
                  coordinator.spotlight?.persistentItemID == expectedID else { return }
            proxy.scrollTo(positionID, anchor: .center)
        }
    }
}

@MainActor
private struct SpotlightShelfTerminalActivity: View {
    @ObservedObject var activityState: TerminalTabActivityState
    let color: Color

    var body: some View {
        ZStack(alignment: .leading) {
            TerminalActivityBar(isActive: activityState.isActive, color: color)
                .frame(width: 3)
                .padding(.vertical, 3)
                .padding(.leading, 2)
            TerminalActivityUnderline(isActive: activityState.isActive, color: color)
                .frame(height: 3)
                .padding(.horizontal, 5)
                .padding(.bottom, 1)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

@MainActor
private struct ShelfDropDelegate: DropDelegate {
    let positionID: UUID
    let size: CGSize
    let onHover: (SpotlightDropZone?) -> Void
    let onDrop: (UUID, SpotlightDropZone, [NSItemProvider]) -> Bool

    func dropEntered(info: DropInfo) { update(info) }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        update(info)
        return DropProposal(operation: .move)
    }
    func dropExited(info: DropInfo) { onHover(nil) }
    func performDrop(info: DropInfo) -> Bool {
        let zone = SpotlightDropZone.resolve(x: info.location.x, width: size.width)
        let result = onDrop(positionID, zone, info.itemProviders(for: [UTType.data]))
        onHover(nil)
        return result
    }
    private func update(_ info: DropInfo) {
        onHover(SpotlightDropZone.resolve(x: info.location.x, width: size.width))
    }
}

@MainActor
private struct SpotlightShelfScrollRegistration: NSViewRepresentable {
    let coordinator: TerminalSpotlightCoordinator

    func makeNSView(context: Context) -> ShelfRegistrationView {
        let view = ShelfRegistrationView()
        view.onScrollViewChanged = { [weak coordinator] scrollView in
            coordinator?.registerShelfScrollView(scrollView)
        }
        return view
    }

    func updateNSView(_ nsView: ShelfRegistrationView, context: Context) {
        nsView.resolveScrollView()
    }

    static func dismantleNSView(_ nsView: ShelfRegistrationView, coordinator: Void) {
        nsView.onScrollViewChanged?(nil)
        nsView.onScrollViewChanged = nil
    }
}

@MainActor
private final class ShelfRegistrationView: NSView {
    var onScrollViewChanged: ((NSScrollView?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        resolveScrollView()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        resolveScrollView()
    }

    func resolveScrollView() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onScrollViewChanged?(self.enclosingScrollView)
        }
    }
}

@MainActor
private struct SpotlightShelfHitRegionRegistration: NSViewRepresentable {
    let coordinator: TerminalSpotlightCoordinator
    let isExcluded: Bool

    func makeNSView(context: Context) -> ShelfHitRegionView {
        let view = ShelfHitRegionView()
        view.onAttachmentChanged = { [weak coordinator] attachedView in
            if isExcluded {
                coordinator?.registerShelfExcludedRegion(attachedView)
            } else {
                coordinator?.registerShelfHitRegion(attachedView)
            }
        }
        return view
    }

    func updateNSView(_ nsView: ShelfHitRegionView, context: Context) {
        nsView.reportAttachment()
    }

    static func dismantleNSView(_ nsView: ShelfHitRegionView, coordinator: Void) {
        nsView.onAttachmentChanged?(nil)
        nsView.onAttachmentChanged = nil
    }
}

@MainActor
private final class ShelfHitRegionView: NSView {
    var onAttachmentChanged: ((NSView?) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reportAttachment()
    }

    func reportAttachment() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onAttachmentChanged?(self.window == nil ? nil : self)
        }
    }
}
