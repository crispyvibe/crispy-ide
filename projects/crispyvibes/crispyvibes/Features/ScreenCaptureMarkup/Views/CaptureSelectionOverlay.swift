import SwiftUI

/// One display-local capture overlay; all instances share one selection view model.
@MainActor
struct CaptureSelectionOverlay: View {
    let display: ScreenCaptureDisplayDescriptor
    @ObservedObject var viewModel: CaptureSelectionViewModel
    @State private var regionDragStarted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack {
            Color.black.opacity(reduceTransparency ? 0.55 : 0.28)
                .ignoresSafeArea()
            targetHighlights
            interactionSurface
            VStack(spacing: 12) {
                controls
                Spacer()
                if viewModel.boundaryResistanceVisible, viewModel.regionDisplayID == display.id {
                    Text(AppStrings.ScreenCapture.regionLimitedToDisplay)
                        .font(.headline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .accessibilityAddTraits(.isStaticText)
                        .accessibilityIdentifier("screenCapture.selection.boundaryMessage")
                }
                selectionAids
                    .padding(.bottom, 28)
            }
            .padding(16)
            if let countdown = viewModel.countdown {
                Text(AppStrings.ScreenCapture.countdown(countdown))
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .padding(30)
                    .background(.ultraThinMaterial, in: Circle())
                    .accessibilityAddTraits(.updatesFrequently)
                    .accessibilityIdentifier("screenCapture.selection.countdown")
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: viewModel.highlightedWindowID)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screenCapture.selection.overlay.\(display.id)")
    }

    private var interactionSurface: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { value in
                    guard viewModel.countdown == nil else { return }
                    if viewModel.mode == .region {
                        if !regionDragStarted {
                            regionDragStarted = true
                            viewModel.beginRegion(on: display.id, swiftUIPoint: value.startLocation)
                        }
                        viewModel.updateRegion(on: display.id, swiftUIPoint: value.location)
                    } else {
                        viewModel.hover(on: display.id, swiftUIPoint: value.location)
                    }
                }
                .onEnded { value in
                    defer { regionDragStarted = false }
                    if viewModel.mode == .region {
                        viewModel.finishRegion(on: display.id, swiftUIPoint: value.location)
                    } else {
                        viewModel.clickTarget(on: display.id, swiftUIPoint: value.location)
                    }
                })
            .onContinuousHover { phase in
                if case .active(let point) = phase {
                    viewModel.hover(on: display.id, swiftUIPoint: point)
                }
            }
            .accessibilityLabel(AppStrings.ScreenCapture.selectionCanvas)
            .accessibilityHint(AppStrings.ScreenCapture.selectionCanvasHint(viewModel.mode))
            .accessibilityAction(named: AppStrings.ScreenCapture.commitSelection) {
                viewModel.commitCurrentTarget()
            }
            .accessibilityAdjustableAction { direction in
                switch (viewModel.mode, direction) {
                case (.region, .increment): viewModel.adjustRegion(horizontal: 1, vertical: 0, largeStep: false)
                case (.region, .decrement): viewModel.adjustRegion(horizontal: -1, vertical: 0, largeStep: false)
                case (_, .increment): viewModel.traverseTarget(forward: true)
                case (_, .decrement): viewModel.traverseTarget(forward: false)
                default: break
                }
            }
            .accessibilityAction(named: AppStrings.ScreenCapture.nextRegionEdge) {
                viewModel.traverseTarget(forward: true)
            }
            .accessibilityIdentifier("screenCapture.selection.canvas.\(display.id)")
    }

    @ViewBuilder
    private var targetHighlights: some View {
        if viewModel.mode == .region,
           viewModel.regionDisplayID == display.id,
           let rect = viewModel.regionLocalRect {
            Rectangle()
                .fill(Color.clear)
                .overlay(Rectangle().stroke(
                    differentiateWithoutColor ? Color.primary : Color.white,
                    style: StrokeStyle(lineWidth: contrast == .increased ? 4 : 2, dash: differentiateWithoutColor ? [8, 4] : [])
                ))
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: display.appKitFrame.height - rect.midY)
                .accessibilityHidden(true)
        } else if viewModel.mode == .window {
            ForEach(viewModel.localWindowRects(on: display.id), id: \.0) { id, rect in
                Rectangle()
                    .fill(id == viewModel.highlightedWindowID ? Color.accentColor.opacity(0.18) : Color.clear)
                    .overlay(Rectangle().stroke(id == viewModel.highlightedWindowID ? Color.accentColor : .white.opacity(0.35), lineWidth: id == viewModel.highlightedWindowID ? 3 : 1))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                    .accessibilityElement()
                    .accessibilityLabel(AppStrings.ScreenCapture.window)
                    .accessibilityAddTraits(id == viewModel.highlightedWindowID ? .isSelected : [])
                    .accessibilityAction {
                        viewModel.selectWindow(id)
                        viewModel.commitCurrentTarget()
                    }
                    .accessibilityIdentifier("screenCapture.selection.window.\(id)")
            }
        } else if viewModel.mode == .display, viewModel.highlightedDisplayID == display.id {
            Rectangle().stroke(Color.accentColor, lineWidth: 6).ignoresSafeArea()
                .accessibilityElement()
                .accessibilityLabel(AppStrings.ScreenCapture.display)
                .accessibilityAddTraits(.isSelected)
                .accessibilityAction {
                    viewModel.selectDisplay(display.id)
                    viewModel.commitCurrentTarget()
                }
                .accessibilityIdentifier("screenCapture.selection.display.\(display.id)")
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Picker(AppStrings.ScreenCapture.mode, selection: Binding(
                get: { viewModel.mode },
                set: { viewModel.selectMode($0) }
            )) {
                Text(AppStrings.ScreenCapture.region).tag(CaptureMode.region)
                Text(AppStrings.ScreenCapture.window).tag(CaptureMode.window)
                Text(AppStrings.ScreenCapture.display).tag(CaptureMode.display)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .accessibilityIdentifier("screenCapture.selection.mode")

            Picker(AppStrings.ScreenCapture.delay, selection: Binding(
                get: { viewModel.options.delay },
                set: { viewModel.selectDelay($0) }
            )) {
                Text(AppStrings.ScreenCapture.delayNone).tag(CaptureDelay.none)
                Text(AppStrings.ScreenCapture.delaySeconds(3)).tag(CaptureDelay.threeSeconds)
                Text(AppStrings.ScreenCapture.delaySeconds(5)).tag(CaptureDelay.fiveSeconds)
                Text(AppStrings.ScreenCapture.delaySeconds(10)).tag(CaptureDelay.tenSeconds)
            }
            .pickerStyle(.menu)
            .fixedSize()
            .accessibilityIdentifier("screenCapture.selection.delay")

            Toggle(AppStrings.ScreenCapture.includePointer, isOn: Binding(
                get: { viewModel.options.includesPointer },
                set: { viewModel.setIncludesPointer($0) }
            ))
            .toggleStyle(.checkbox)
            .fixedSize()
            .accessibilityIdentifier("screenCapture.selection.includePointer")

            Button(AppStrings.ScreenCapture.cancel) { viewModel.cancel() }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("screenCapture.selection.cancel")
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .disabled(viewModel.countdown != nil)
    }

    @ViewBuilder
    private var selectionAids: some View {
        if viewModel.mode == .region, viewModel.regionDisplayID == display.id {
            HStack(spacing: 12) {
                if let magnifier = viewModel.magnifierImage {
                    VStack(spacing: 4) {
                        Text(AppStrings.ScreenCapture.pointerMagnifier)
                            .font(.caption.weight(.semibold))
                        ZStack {
                            Image(decorative: magnifier, scale: 1)
                                .resizable()
                                .interpolation(.none)
                                .frame(width: 100, height: 100)
                                .accessibilityHidden(true)
                            Rectangle()
                                .fill(.white)
                                .frame(width: 15, height: 1)
                            Rectangle()
                                .fill(.white)
                                .frame(width: 1, height: 15)
                        }
                        .frame(width: 100, height: 100)
                        .overlay(Rectangle().stroke(.white, lineWidth: 1))
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("screenCapture.selection.pointerMagnifier")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(viewModel.dimensionsText)
                        .font(.system(.title3, design: .monospaced).weight(.semibold))
                        .accessibilityAddTraits(.updatesFrequently)
                        .accessibilityIdentifier("screenCapture.selection.dimensions")
                    Text(AppStrings.ScreenCapture.regionEdge(viewModel.activeRegionEdge))
                        .font(.caption)
                    Text(AppStrings.ScreenCapture.regionKeyboardHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
    }
}
