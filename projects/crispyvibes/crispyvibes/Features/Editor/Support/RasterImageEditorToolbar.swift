import AppKit
import SwiftUI

/// Controls which F009 actions are exposed by a raster editor host.
struct RasterImageEditorToolbarConfiguration {
    let modes: [RasterImageEditingMode]
    let showsVision: Bool
    let showsCopy: Bool
    let showsExport: Bool
    let showsFileSave: Bool
    let accessibilityPrefix: String

    /// Existing file-backed editor behavior.
    static let fileBacked = RasterImageEditorToolbarConfiguration(
        modes: RasterImageEditingMode.allCases,
        showsVision: true,
        showsCopy: true,
        showsExport: true,
        showsFileSave: true,
        accessibilityPrefix: "editor.preview.image"
    )

    /// In-memory Screen Capture editor behavior; delivery is owned by F062.
    static let screenCapture = RasterImageEditorToolbarConfiguration(
        modes: [.markup, .crop],
        showsVision: false,
        showsCopy: false,
        showsExport: false,
        showsFileSave: false,
        accessibilityPrefix: "screenCapture.markup"
    )
}

/// Image editor toolbar: modes, actions, crop/geometry controls, status line, and zoom.
@MainActor
struct RasterImageEditorToolbar: View {
    @ObservedObject var viewModel: RasterImageEditorViewModel
    let onSave: () -> Void
    var configuration: RasterImageEditorToolbarConfiguration = .fileBacked
    @Environment(\.appThemePalette) private var appThemePalette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            actionRow
            if viewModel.editingMode == .crop {
                cropRow
            }
            if viewModel.editingMode == .markup {
                RasterImageMarkupToolbar(viewModel: viewModel, accessibilityPrefix: configuration.accessibilityPrefix)
            }
            if viewModel.editingMode == .adjust {
                RasterImageAdjustToolbar(viewModel: viewModel)
            }
            if viewModel.hasExternalChangeConflict {
                conflictBanner
            }
            HStack(spacing: 8) {
                Text(viewModel.statusLine)
                    .font(AppTypographyTokens.imageStatus)
                    .foregroundStyle(appThemePalette.secondaryTextColor)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("\(configuration.accessibilityPrefix).status")
                    .accessibilityAddTraits(.updatesFrequently)
                zoomControls
            }
        }
        .buttonStyle(.crispyvibesText)
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(appThemePalette.windowBackgroundColor.opacity(0.92))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(configuration.accessibilityPrefix).toolbar")
    }

    private var actionRow: some View {
        HStack(spacing: 8) {
            modePicker
            if viewModel.canvasState.hasCropSelection {
                Divider().frame(height: 18)
                Button(AppStrings.ImageEditor.applyCrop) { viewModel.applyCrop() }
                    .disabled(!viewModel.canApplyCrop)
                    .accessibilityIdentifier("\(configuration.accessibilityPrefix).action.apply-crop")
                Button(AppStrings.ImageEditor.cancelCrop) { viewModel.cancelCrop() }
                    .disabled(!viewModel.canCancelCrop)
                    .accessibilityIdentifier("\(configuration.accessibilityPrefix).action.cancel-crop")
            }
            Spacer(minLength: 8)
            iconButton(AppStrings.ImageEditor.undo, systemImage: "arrow.uturn.backward", id: "undo", enabled: viewModel.canUndo) {
                viewModel.undo()
            }
            iconButton(AppStrings.ImageEditor.redo, systemImage: "arrow.uturn.forward", id: "redo", enabled: viewModel.canRedo) {
                viewModel.redo()
            }
            if configuration.showsVision {
                RasterImageVisionMenu(viewModel: viewModel)
            }
            if configuration.showsCopy {
                Button(AppStrings.ImageEditor.copy) { viewModel.copy() }
                    .disabled(!viewModel.canCopy)
                    .accessibilityIdentifier("\(configuration.accessibilityPrefix).action.copy")
            }
            Button(AppStrings.ImageEditor.revert) { viewModel.revert() }
                .disabled(!viewModel.canRevert)
                .accessibilityIdentifier("\(configuration.accessibilityPrefix).action.clear")
            if configuration.showsExport {
                Button(AppStrings.ImageEditor.exportAs) { viewModel.presentExport() }
                    .disabled(!viewModel.canExport)
                    .accessibilityIdentifier("\(configuration.accessibilityPrefix).action.export")
            }
            if configuration.showsFileSave {
                Button(AppStrings.ImageEditor.save, action: onSave)
                    .disabled(!viewModel.canSave)
                    .accessibilityIdentifier("\(configuration.accessibilityPrefix).action.save")
            }
            if viewModel.isSaving || viewModel.isExporting {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var modePicker: some View {
        Picker("", selection: Binding(
            get: { viewModel.editingMode },
            set: { viewModel.selectMode($0) }
        )) {
            ForEach(configuration.modes, id: \.self) { mode in
                Text(mode.title)
                    .tag(mode)
                    .accessibilityIdentifier("\(configuration.accessibilityPrefix).mode.\(mode.rawValue)")
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .disabled(viewModel.isSaving)
        .accessibilityIdentifier("\(configuration.accessibilityPrefix).mode")
    }

    private var cropRow: some View {
        HStack(spacing: 8) {
            Picker(AppStrings.ImageEditor.aspectRatio, selection: Binding(
                get: { viewModel.cropAspectRatio },
                set: { viewModel.selectCropAspectRatio($0) }
            )) {
                ForEach(RasterImageCropAspectRatio.allCases) { ratio in
                    Text(ratio.title).tag(ratio)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .accessibilityIdentifier("\(configuration.accessibilityPrefix).crop.aspect")
            iconButton(AppStrings.ImageEditor.cropOrientation, systemImage: "rectangle.portrait.rotate", id: "crop-orientation",
                       enabled: viewModel.cropAspectRatio.isOrientable) {
                viewModel.toggleCropOrientation()
            }
            Divider().frame(height: 18)
            iconButton(AppStrings.ImageEditor.rotateLeft, systemImage: "rotate.left", id: "rotate-left", enabled: viewModel.canEditGeometry) {
                viewModel.rotate(clockwise: false)
            }
            iconButton(AppStrings.ImageEditor.rotateRight, systemImage: "rotate.right", id: "rotate-right", enabled: viewModel.canEditGeometry) {
                viewModel.rotate(clockwise: true)
            }
            iconButton(AppStrings.ImageEditor.flipHorizontal, systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right",
                       id: "flip-horizontal", enabled: viewModel.canEditGeometry) {
                viewModel.flip(horizontal: true)
            }
            iconButton(AppStrings.ImageEditor.flipVertical, systemImage: "arrow.up.and.down.righttriangle.up.righttriangle.down",
                       id: "flip-vertical", enabled: viewModel.canEditGeometry) {
                viewModel.flip(horizontal: false)
            }
            Divider().frame(height: 18)
            Text(AppStrings.ImageEditor.straighten)
                .font(AppTypographyTokens.imageStatus)
            Slider(
                value: Binding(get: { viewModel.straightenDegrees }, set: { viewModel.previewStraighten(degrees: $0) }),
                in: -45...45,
                onEditingChanged: { editing in if !editing { viewModel.commitStraighten() } }
            )
            .frame(minWidth: 120, maxWidth: 200)
            .disabled(!viewModel.canEditGeometry)
            .accessibilityLabel(AppStrings.ImageEditor.straighten)
            .accessibilityValue(AppStrings.ImageEditor.straightenValue(viewModel.straightenDegrees))
            .accessibilityIdentifier("\(configuration.accessibilityPrefix).straighten")
            Text(AppStrings.ImageEditor.straightenValue(viewModel.straightenDegrees))
                .font(AppTypographyTokens.imageStatus)
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
            Spacer(minLength: 8)
            Button(AppStrings.ImageEditor.resize) { viewModel.presentResize() }
                .disabled(!viewModel.canEditGeometry)
                .accessibilityIdentifier("\(configuration.accessibilityPrefix).action.resize")
        }
    }

    private var conflictBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(appThemePalette.warningColor)
                .accessibilityHidden(true)
            Text(AppStrings.ImageEditor.statusExternalChange)
                .font(AppTypographyTokens.imageStatus)
            Spacer(minLength: 8)
            Button(AppStrings.ImageEditor.reloadFromDisk) { viewModel.reloadFromDisk() }
                .accessibilityIdentifier("\(configuration.accessibilityPrefix).action.reload")
            Button(AppStrings.ImageEditor.keepMine) { viewModel.keepMyEdits() }
                .accessibilityIdentifier("\(configuration.accessibilityPrefix).action.keep-mine")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(configuration.accessibilityPrefix).conflict")
    }

    private var zoomControls: some View {
        HStack(spacing: 4) {
            iconButton(AppStrings.ImageEditor.zoomOut, systemImage: "minus.magnifyingglass", id: "zoom-out", enabled: viewModel.hasRenderableImage) {
                viewModel.zoomOut()
            }
            Menu(AppStrings.ImageEditor.zoomPercent(Int(viewModel.zoomPercent.rounded()))) {
                Button(AppStrings.ImageEditor.zoomToFit) { viewModel.fitToWindow() }
                Button(AppStrings.ImageEditor.zoomActualSize) { viewModel.zoomToActualSize() }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(!viewModel.hasRenderableImage)
            .accessibilityIdentifier("\(configuration.accessibilityPrefix).zoom")
            iconButton(AppStrings.ImageEditor.zoomIn, systemImage: "plus.magnifyingglass", id: "zoom-in", enabled: viewModel.hasRenderableImage) {
                viewModel.zoomIn()
            }
        }
    }

    private func iconButton(
        _ title: String,
        systemImage: String,
        id: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, systemImage: systemImage, action: action)
            .labelStyle(.iconOnly)
            .help(title)
            .disabled(!enabled)
            .accessibilityIdentifier("\(configuration.accessibilityPrefix).action.\(id)")
    }
}

extension RasterImageCropAspectRatio {
    /// Menu title.
    var title: String {
        switch self {
        case .free: return AppStrings.ImageEditor.aspectFree
        case .original: return AppStrings.ImageEditor.aspectOriginal
        case .square: return AppStrings.ImageEditor.aspectSquare
        case .ratio4x3: return AppStrings.ImageEditor.aspectRatio(width: 4, height: 3)
        case .ratio3x2: return AppStrings.ImageEditor.aspectRatio(width: 3, height: 2)
        case .ratio16x9: return AppStrings.ImageEditor.aspectRatio(width: 16, height: 9)
        }
    }
}
