import SwiftUI

/// Floating control pad rendered in the bottom-right of every terminal (F046).
///
/// Three buttons: ⬆ jump to previous user message, ⬇ jump to next user message,
/// 🔍 toggle search. Translucent at rest, full opacity on hover or when search is open.
struct TerminalScrollbackSearchOverlay: View {
    let session: TerminalSession
    let isHostHovered: Bool
    var onSplitTerminal: (() -> Void)? = nil
    var onTemporaryTerminal: (() -> Void)? = nil

    @StateObject private var viewModel: TerminalScrollAssistViewModel
    @State private var isHovering = false
    @State private var isPadExpanded = false
    @State private var padOffset: CGSize = .zero
    @State private var dragStartOffset: CGSize = .zero
    @FocusState private var isSearchFieldFocused: Bool

    init(session: TerminalSession, isHostHovered: Bool, onSplitTerminal: (() -> Void)? = nil, onTemporaryTerminal: (() -> Void)? = nil) {
        self.session = session
        self.isHostHovered = isHostHovered
        self.onSplitTerminal = onSplitTerminal
        self.onTemporaryTerminal = onTemporaryTerminal
        _viewModel = StateObject(wrappedValue: TerminalScrollAssistViewModel(session: session))
    }

    private var shouldShow: Bool {
        true // ball is always visible; D-pad expands on hover
    }

    var body: some View {
        GeometryReader { proxy in
            if shouldShow {
                adaptiveLayout(containerWidth: proxy.size.width)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: shouldShow)
    }

    /// Threshold below which we stack the search panel above the pad instead of beside it.
    private static let narrowLayoutThreshold: CGFloat = 460

    @ViewBuilder
    private func adaptiveLayout(containerWidth: CGFloat) -> some View {
        let isNarrow = containerWidth < Self.narrowLayoutThreshold
        let panelMaxWidth = max(220, min(340, containerWidth - 32))

        if isNarrow {
            ScrollAssistGlassContainer(spacing: 8) {
                VStack(alignment: .trailing, spacing: 8) {
                    if viewModel.isSearchVisible {
                        searchPanel
                            .frame(maxWidth: panelMaxWidth)
                            .transition(.asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .move(edge: .bottom).combined(with: .opacity)
                            ))
                    }
                    controlPad
                }
            }
            .padding(16)
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: viewModel.isSearchVisible)
        } else {
            ScrollAssistGlassContainer(spacing: 8) {
                HStack(alignment: .center, spacing: 8) {
                    if viewModel.isSearchVisible {
                        searchPanel
                            .frame(maxWidth: panelMaxWidth)
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .trailing).combined(with: .opacity)
                            ))
                    }
                    controlPad
                }
            }
            .padding(16)
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: viewModel.isSearchVisible)
        }
    }

    // MARK: - Control Pad (D-pad cross layout)

    private var controlPad: some View {
        Group {
            if isPadExpanded {
                expandedDPad
            } else {
                collapsedBall
            }
        }
        .offset(padOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    padOffset = CGSize(
                        width: dragStartOffset.width + value.translation.width,
                        height: dragStartOffset.height + value.translation.height
                    )
                }
                .onEnded { _ in
                    dragStartOffset = padOffset
                }
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.7, blendDuration: 0.1), value: isPadExpanded)
    }

    private var collapsedBall: some View {
        Circle()
            .fill(.ultraThinMaterial)
            .frame(width: 24, height: 24)
            .overlay(
                Image(systemName: "circle.grid.cross")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.5))
            )
            .opacity(0.45)
            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
            .scaleEffect(1.0)
            .transition(.scale(scale: 0.5).combined(with: .opacity))
            .onHover { hovering in
                if hovering { isPadExpanded = true }
            }
            .onTapGesture {
                isPadExpanded = true
            }
    }

    private var expandedDPad: some View {
        VStack(spacing: 2) {
            padButton(systemName: "arrow.up", isEnabled: viewModel.canNavigatePrevious) {
                viewModel.navigatePrevious()
            }

            HStack(spacing: 2) {
                padButton(systemName: "scope", isEnabled: true) {
                    onTemporaryTerminal?()
                }
                padButton(
                    systemName: viewModel.isSearchVisible ? "xmark" : "magnifyingglass",
                    isEnabled: true,
                    isCenter: true
                ) {
                    viewModel.toggleSearch()
                    if viewModel.isSearchVisible {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            isSearchFieldFocused = true
                        }
                    }
                }
                padButton(systemName: "square.split.2x1", isEnabled: true) {
                    onSplitTerminal?()
                }
            }

            padButton(systemName: "arrow.down", isEnabled: viewModel.canNavigateNext) {
                viewModel.navigateNext()
            }
        }
        .transition(.scale(scale: 0.3).combined(with: .opacity))
        .onHover { hovering in
            isHovering = hovering
            if !hovering && !viewModel.isSearchVisible {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    if !isHovering && !viewModel.isSearchVisible {
                        isPadExpanded = false
                    }
                }
            }
        }
    }

    private func padButton(
        systemName: String,
        isEnabled: Bool,
        isCenter: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Image(systemName: systemName)
            .font(.system(size: isCenter ? 12 : 11, weight: .semibold))
            .foregroundStyle(isEnabled ? Color.primary.opacity(0.85) : Color.primary.opacity(0.25))
            .frame(width: 28, height: 28)
            .scrollAssistGlassBackground(in: Circle())
            .contentShape(Circle())
            .onTapGesture {
                guard isEnabled else { return }
                action()
            }
    }

    // MARK: - Search Panel

    private var searchPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            searchBar
            if !viewModel.matches.isEmpty {
                Divider()
                resultsList
            } else if !viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Divider()
                noResultsView
            }
        }
        .frame(minWidth: 220, idealWidth: 340, maxWidth: 340)
        .scrollAssistGlassBackground(in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.18), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            TextField("Search scrollback…", text: $viewModel.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .focused($isSearchFieldFocused)
                .onChange(of: viewModel.searchQuery) { _, _ in
                    viewModel.runSearch()
                }
                .onKeyPress(.escape) {
                    viewModel.closeSearch()
                    return .handled
                }

            if !viewModel.matches.isEmpty {
                Text("\(viewModel.matches.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(viewModel.matches) { match in
                    resultRow(match)
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 220)
    }

    private func resultRow(_ match: TerminalScrollbackReader.Match) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\(match.lineIndex)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 36, alignment: .trailing)

            Text(sanitized(match.lineText))
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(2)
                .truncationMode(.tail)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.scrollToMatch(match)
        }
    }

    private var noResultsView: some View {
        Text("No matches")
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 12)
    }

    /// Strip control characters from a line so escape sequences in scrollback
    /// can't mess with the SwiftUI text rendering or hide content (F046-T02).
    private func sanitized(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let safe = trimmed.unicodeScalars.filter { scalar in
            scalar.value == 0x09 || (scalar.value >= 0x20 && scalar.value < 0x7F) || scalar.value > 0x7F
        }
        return String(String.UnicodeScalarView(safe)).prefix(200).description
    }
}
