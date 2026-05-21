import AppKit
import SwiftUI

final class OverflowHostingView<Content: View>: NSHostingView<Content> {
    override var wantsDefaultClipping: Bool {
        false
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        wantsLayer = true
        layer?.masksToBounds = false
    }
}

private final class TrackingSplitView: NSSplitView {
    var onDividerDragStarted: (() -> Void)?
    var onDividerDragEnded: (() -> Void)?
    var customDividerColor: NSColor = .clear

    override var wantsDefaultClipping: Bool {
        false
    }

    override var dividerThickness: CGFloat {
        2
    }

    override func drawDivider(in rect: NSRect) {
        // Intentionally empty — no visible border between panes
    }

    override func mouseDown(with event: NSEvent) {
        let pointInSplitView = convert(event.locationInWindow, from: nil)
        if isPointNearDivider(pointInSplitView) {
            onDividerDragStarted?()
            super.mouseDown(with: event)
            onDividerDragEnded?()
            return
        }
        super.mouseDown(with: event)
    }

    private func isPointNearDivider(_ point: NSPoint) -> Bool {
        guard subviews.count >= 2 else { return false }

        let firstSubviewFrame = subviews[0].frame
        let tolerance = dividerThickness + 2

        if isVertical {
            return abs(point.x - firstSubviewFrame.maxX) <= tolerance
        }
        return abs(point.y - firstSubviewFrame.maxY) <= tolerance
    }
}

struct NativeSplitView<Primary: View, Secondary: View>: NSViewRepresentable {
    let isVerticalSplit: Bool
    let primaryAtEnd: Bool
    @Binding var primarySize: CGFloat
    let minPrimary: CGFloat
    let maxPrimary: CGFloat
    let minSecondary: CGFloat
    let primary: () -> Primary
    let secondary: () -> Secondary

    init(
        isVerticalSplit: Bool,
        primaryAtEnd: Bool,
        primarySize: Binding<CGFloat>,
        minPrimary: CGFloat,
        maxPrimary: CGFloat,
        minSecondary: CGFloat = 0,
        @ViewBuilder primary: @escaping () -> Primary,
        @ViewBuilder secondary: @escaping () -> Secondary
    ) {
        self.isVerticalSplit = isVerticalSplit
        self.primaryAtEnd = primaryAtEnd
        self._primarySize = primarySize
        self.minPrimary = minPrimary
        self.maxPrimary = maxPrimary
        self.minSecondary = minSecondary
        self.primary = primary
        self.secondary = secondary
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSSplitView {
        let splitView = TrackingSplitView(frame: .zero)
        splitView.isVertical = isVerticalSplit
        splitView.dividerStyle = .thin
        splitView.wantsLayer = true
        splitView.layer?.masksToBounds = false
        splitView.customDividerColor = context.coordinator.resolvedDividerColor(
            for: splitView.effectiveAppearance
        )
        splitView.delegate = context.coordinator
        splitView.onDividerDragStarted = { [weak coordinator = context.coordinator] in
            coordinator?.beginDividerDrag()
        }
        splitView.onDividerDragEnded = { [weak coordinator = context.coordinator] in
            coordinator?.endDividerDrag()
        }

        let firstHost = context.coordinator.firstHost
        let secondHost = context.coordinator.secondHost

        splitView.addArrangedSubview(firstHost)
        splitView.addArrangedSubview(secondHost)

        context.coordinator.attach(splitView)
        context.coordinator.updateHostedContent(primary: primary(), secondary: secondary())
        context.coordinator.applyDividerPositionIfNeeded(force: true)

        return splitView
    }

    func updateNSView(_ splitView: NSSplitView, context: Context) {
        splitView.isVertical = isVerticalSplit
        if let trackingSplitView = splitView as? TrackingSplitView {
            trackingSplitView.customDividerColor = context.coordinator.resolvedDividerColor(
                for: splitView.effectiveAppearance
            )
            trackingSplitView.needsDisplay = true
        }
        context.coordinator.parent = self
        context.coordinator.updateHostedContent(primary: primary(), secondary: secondary())
        context.coordinator.applyDividerPositionIfNeeded(force: false)
    }

    final class Coordinator: NSObject, NSSplitViewDelegate {
        var parent: NativeSplitView
        let firstHost = OverflowHostingView(rootView: AnyView(EmptyView()))
        let secondHost = OverflowHostingView(rootView: AnyView(EmptyView()))

        private weak var splitView: NSSplitView?
        private var isApplyingProgrammaticPosition = false
        private var isUserDraggingDivider = false
        private var isDeferredApplyScheduled = false
        private var pendingDeferredApplyForce = false
        private var dividerColorByScheme: [ColorScheme: NSColor] = [:]
        private var dividerThemeSnapshot = DividerThemeSnapshot.capture()
        private var defaultsObserver: NSObjectProtocol?

        private struct DividerThemeSnapshot: Equatable {
            let appearancePreferenceRaw: String
            let themePresetRaw: String
            let customThemeJSON: String

            static func capture(defaults: UserDefaults = .standard) -> DividerThemeSnapshot {
                DividerThemeSnapshot(
                    appearancePreferenceRaw: defaults.string(forKey: AppPreferences.appearancePreferenceKey)
                        ?? AppPreferences.defaultAppearancePreference,
                    themePresetRaw: defaults.string(forKey: AppPreferences.appThemePresetKey)
                        ?? AppPreferences.defaultAppThemePreset,
                    customThemeJSON: defaults.string(forKey: AppPreferences.appCustomThemePaletteJSONKey)
                        ?? ""
                )
            }
        }

        init(parent: NativeSplitView) {
            self.parent = parent
            super.init()
            defaultsObserver = NotificationCenter.default.addObserver(
                forName: UserDefaults.didChangeNotification,
                object: UserDefaults.standard,
                queue: .main
            ) { [weak self] _ in
                self?.refreshThemeSnapshotIfNeeded()
            }
        }

        deinit {
            if let defaultsObserver {
                NotificationCenter.default.removeObserver(defaultsObserver)
            }
        }

        func attach(_ splitView: NSSplitView) {
            self.splitView = splitView
        }

        func resolvedDividerColor(for appearance: NSAppearance) -> NSColor {
            let systemScheme: ColorScheme =
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
            if let cached = dividerColorByScheme[systemScheme] {
                return cached
            }

            let palette = AppThemeResolver.palette(
                appearancePreferenceRaw: dividerThemeSnapshot.appearancePreferenceRaw,
                fallbackSystemColorScheme: systemScheme,
                themePresetRaw: dividerThemeSnapshot.themePresetRaw,
                customThemeJSON: dividerThemeSnapshot.customThemeJSON
            )
            let color = palette.windowBackground.nsColor.withAlphaComponent(1.0)
            dividerColorByScheme[systemScheme] = color
            return color
        }

        func beginDividerDrag() {
            isUserDraggingDivider = true
        }

        func endDividerDrag() {
            isUserDraggingDivider = false
            scheduleDeferredApply(force: true)
        }

        func updateHostedContent(primary: Primary, secondary: Secondary) {
            let newPrimary = AnyView(primary)
            let newSecondary = AnyView(secondary)
            if parent.primaryAtEnd {
                firstHost.rootView = newSecondary
                secondHost.rootView = newPrimary
            } else {
                firstHost.rootView = newPrimary
                secondHost.rootView = newSecondary
            }
        }

        func splitView(
            _ splitView: NSSplitView,
            canCollapseSubview subview: NSView
        ) -> Bool {
            false
        }

        func splitView(
            _ splitView: NSSplitView,
            constrainSplitPosition proposedPosition: CGFloat,
            ofSubviewAt dividerIndex: Int
        ) -> CGFloat {
            let dividerThickness = splitView.dividerThickness
            let total = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
            guard total > dividerThickness else { return proposedPosition }

            if parent.primaryAtEnd {
                let proposedPrimary = total - proposedPosition - dividerThickness
                let clampedPrimary = clampedPrimarySize(proposedPrimary, in: splitView)
                persistPrimarySizeIfNeeded(clampedPrimary)
                return total - clampedPrimary - dividerThickness
            }

            let clampedPrimary = clampedPrimarySize(proposedPosition, in: splitView)
            persistPrimarySizeIfNeeded(clampedPrimary)
            return clampedPrimary
        }

        func applyDividerPositionIfNeeded(force: Bool) {
            guard let splitView,
                  splitView.subviews.count >= 2 else { return }
            guard force || !isUserDraggingDivider else { return }

            let dividerThickness = splitView.dividerThickness
            let total = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
            guard total > dividerThickness else {
                scheduleDeferredApply(force: force)
                return
            }
            let firstPaneFrame = splitView.subviews[0].frame
            let currentPosition = splitView.isVertical ? firstPaneFrame.width : firstPaneFrame.height
            guard total > 0,
                  currentPosition.isFinite else {
                scheduleDeferredApply(force: force)
                return
            }

            let clampedPrimary = clampedPrimarySize(parent.primarySize, in: splitView)
            let desiredPosition: CGFloat
            if parent.primaryAtEnd {
                desiredPosition = total - clampedPrimary - dividerThickness
            } else {
                desiredPosition = clampedPrimary
            }

            guard desiredPosition.isFinite else {
                scheduleDeferredApply(force: force)
                return
            }
            guard force || abs(currentPosition - desiredPosition) > 0.5 else { return }

            isApplyingProgrammaticPosition = true
            splitView.setPosition(desiredPosition, ofDividerAt: 0)
            splitView.adjustSubviews()
            isApplyingProgrammaticPosition = false
        }

        private func clampedPrimarySize(_ proposed: CGFloat, in splitView: NSSplitView) -> CGFloat {
            let dividerThickness = splitView.dividerThickness
            let total = splitView.isVertical ? splitView.bounds.width : splitView.bounds.height
            let maximumForPrimary = max(parent.minPrimary, total - dividerThickness - parent.minSecondary)
            let upperBound = min(parent.maxPrimary, maximumForPrimary)
            return clamped(proposed, min: parent.minPrimary, max: upperBound)
        }

        private func persistPrimarySizeIfNeeded(_ clampedPrimary: CGFloat) {
            guard !isApplyingProgrammaticPosition else { return }
            guard isUserDraggingDivider else { return }
            guard abs(parent.primarySize - clampedPrimary) > 0.5 else { return }
            parent.primarySize = clampedPrimary
        }

        private func scheduleDeferredApply(force: Bool) {
            pendingDeferredApplyForce = pendingDeferredApplyForce || force
            guard !isDeferredApplyScheduled else { return }
            isDeferredApplyScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.isDeferredApplyScheduled = false
                let shouldForce = self.pendingDeferredApplyForce
                self.pendingDeferredApplyForce = false
                self.applyDividerPositionIfNeeded(force: shouldForce)
            }
        }

        private func refreshThemeSnapshotIfNeeded() {
            let updatedSnapshot = DividerThemeSnapshot.capture()
            guard updatedSnapshot != dividerThemeSnapshot else { return }
            dividerThemeSnapshot = updatedSnapshot
            dividerColorByScheme.removeAll(keepingCapacity: true)
            applyCurrentDividerColorIfNeeded()
        }

        private func applyCurrentDividerColorIfNeeded() {
            guard let splitView,
                  let trackingSplitView = splitView as? TrackingSplitView else { return }
            let resolvedColor = resolvedDividerColor(for: splitView.effectiveAppearance)
            guard trackingSplitView.customDividerColor != resolvedColor else { return }
            trackingSplitView.customDividerColor = resolvedColor
            trackingSplitView.needsDisplay = true
        }

    }
}
